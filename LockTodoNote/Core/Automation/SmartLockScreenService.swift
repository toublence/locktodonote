import BackgroundTasks
import Foundation
import LockTodoNoteShared

/// Foreground transitions are timed locally; background execution is best effort under iOS.
@MainActor
final class SmartLockScreenService {
    static let backgroundTaskIdentifier = "com.namslab.glancecard.smart-lock-screen.refresh"
    private let dashboard: DashboardCoordinator
    private let store: AppGroupStore
    private var task: Task<Void, Never>?
    private var isActive = false

    init(dashboard: DashboardCoordinator, store: AppGroupStore) {
        self.dashboard = dashboard; self.store = store
    }

    func setActive(_ active: Bool) {
        isActive = active
        refresh()
    }

    func refresh() {
        task?.cancel()
        task = nil
        dashboard.publish()
        Self.scheduleBackground(store: store)
        guard isActive, let schedule = try? SmartLockScreenSchedule.load(store: store), schedule.isEnabled,
              Self.entitlement(store).isPro,
              let boundary = schedule.transitionDates(after: Date(), days: 8).first else { return }
        let next = min(boundary, Self.entitlement(store).expirationDate ?? boundary)
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private static func entitlement(_ store: AppGroupStore) -> Entitlement {
        Entitlement(cachedJSON: store.defaults?.string(forKey: FlutterPreferenceKeys.purchaseState))
    }

    private static func scheduleBackground(store: AppGroupStore) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        guard entitlement(store).isPro,
              let schedule = try? SmartLockScreenSchedule.load(store: store), schedule.isEnabled,
              let boundary = schedule.transitionDates(after: Date(), days: 8).first else { return }
        let next = min(boundary, entitlement(store).expirationDate ?? boundary)
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
    }

    static func refreshInBackground() async {
        let store = AppGroupStore()
        defer { scheduleBackground(store: store) }
        let cards = CardStore(repository: CardRepository(store: store))
        guard cards.load() != nil else { return }
        let pro = entitlement(store).isPro
        let defaults = store.defaults
        let now = Date()
        let resolved = SmartLockScreenSchedule.resolve(
            cards: cards.cards, settings: defaults.map(LockScreenSettings.load(from:)) ?? LockScreenSettings(),
            store: store, at: now, isPro: pro
        )
        let followsToday = defaults?.object(forKey: FlutterPreferenceKeys.followToday) as? Bool ?? true
        let date = resolved.ruleID != nil || followsToday ? now
            : defaults?.string(forKey: AppGroupKeys.selectedDate).flatMap { FlutterDate.parse($0) } ?? now
        let snapshot = DashboardComposer(strings: .current).compose(
            cards: resolved.cards, selectedDate: date, settings: resolved.settings,
            privacyMode: PrivacyMode(fromStored: defaults?.string(forKey: FlutterPreferenceKeys.defaultPrivacyMode)), now: now
        )
        await LiveActivityService(store: store).update(snapshot: snapshot, isPro: pro)
    }
}

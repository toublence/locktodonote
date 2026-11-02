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
        guard isActive else { return }
        let next = Self.nextRefresh(store: store)
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.dashboard.refreshForDateBoundary()
            self?.refresh()
        }
    }

    private static func entitlement(_ store: AppGroupStore) -> Entitlement {
        Entitlement(cachedJSON: store.defaults?.string(forKey: FlutterPreferenceKeys.purchaseState))
    }

    /// Midnight refresh also applies to free users without Smart Lock Screen rules.
    private static func nextRefresh(store: AppGroupStore, now: Date = Date()) -> Date {
        var next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
            ?? now.addingTimeInterval(24 * 60 * 60)
        let access = entitlement(store)
        if access.isPro, let schedule = try? SmartLockScreenSchedule.load(store: store), schedule.isEnabled,
           let boundary = schedule.transitionDates(after: now, days: 8).first { next = min(next, boundary) }
        if let expiry = access.expirationDate, expiry > now { next = min(next, expiry) }
        return next
    }

    private static func scheduleBackground(store: AppGroupStore) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        let next = nextRefresh(store: store)
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

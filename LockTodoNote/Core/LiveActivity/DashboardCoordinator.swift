import Foundation
import LockTodoNoteShared

/// The single place where card changes become Lock Screen changes.
///
/// Every mutation funnels through `publish()`, which recomposes the snapshot,
/// writes it to the App Group for the widget, and pushes it to a running Live
/// Activity. Scattering that work across call sites is what let the Flutter
/// build drift out of sync.
@MainActor
final class DashboardCoordinator: ObservableObject {
    enum DateSelectionMode: Equatable {
        case followToday
        case explicitDate
    }

    @Published private(set) var selectedDate: Date
    @Published private(set) var dateSelectionMode: DateSelectionMode
    @Published private(set) var snapshot: DashboardSnapshot?

    weak var analytics: AnalyticsService?
    private var lastResolvedRuleID: UUID?
    private let cardStore: CardStore
    private let settingsStore: LockScreenSettingsStore
    private let liveActivity: LiveActivityService
    private let entitlements: EntitlementProviding
    private let store: AppGroupStore
    private let calendar: Calendar
    private let nowProvider: () -> Date

    var today: Date { nowProvider() }

    init(
        cardStore: CardStore,
        settingsStore: LockScreenSettingsStore,
        liveActivity: LiveActivityService,
        entitlements: EntitlementProviding,
        store: AppGroupStore = AppGroupStore(),
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.cardStore = cardStore
        self.settingsStore = settingsStore
        self.liveActivity = liveActivity
        self.entitlements = entitlements
        self.store = store
        self.calendar = calendar
        self.nowProvider = nowProvider
        let followsToday = store.defaults?.object(forKey: FlutterPreferenceKeys.followToday) as? Bool ?? true
        self.dateSelectionMode = followsToday ? .followToday : .explicitDate
        if !followsToday,
           let raw = store.defaults?.string(forKey: AppGroupKeys.selectedDate),
           let storedDate = FlutterDate.parse(raw) {
            self.selectedDate = storedDate
        } else {
            self.selectedDate = nowProvider()
        }
    }

    var composer: DashboardComposer {
        DashboardComposer(
            strings: .current,
            calendar: calendar,
            localeIdentifier: AppLanguagePreference.resolvedLocaleIdentifier(from: store.defaults)
        )
    }

    func currentSnapshot(now: Date? = nil) -> DashboardSnapshot {
        let now = now ?? nowProvider()
        let effectiveDate = dateSelectionMode == .followToday ? now : selectedDate
        let resolved = SmartLockScreenSchedule.resolve(
            cards: cardStore.cards, settings: settingsStore.settings, store: store,
            at: now, isPro: entitlements.isPro, calendar: calendar
        )
        lastResolvedRuleID = resolved.ruleID
        return composer.compose(
            cards: resolved.cards,
            selectedDate: resolved.ruleID == nil ? effectiveDate : now,
            settings: resolved.settings,
            privacyMode: settingsStore.defaultPrivacyMode,
            now: now
        )
    }

    func followToday(now: Date? = nil) {
        let now = now ?? nowProvider()
        dateSelectionMode = .followToday
        selectedDate = now
        store.defaults?.set(true, forKey: FlutterPreferenceKeys.followToday)
    }

    func selectExplicitDate(_ date: Date) {
        dateSelectionMode = .explicitDate
        selectedDate = date
        store.defaults?.set(false, forKey: FlutterPreferenceKeys.followToday)
        store.defaults?.set(FlutterDate.localString(from: date), forKey: AppGroupKeys.selectedDate)
    }

    func refreshFollowingToday(now: Date? = nil) {
        let now = now ?? nowProvider()
        guard dateSelectionMode == .followToday else { return }
        selectedDate = now
    }

    func refreshSelectionFromSharedDefaults(now: Date? = nil) {
        let now = now ?? nowProvider()
        let followsToday = store.defaults?.object(forKey: FlutterPreferenceKeys.followToday) as? Bool ?? true
        if followsToday {
            dateSelectionMode = .followToday
            selectedDate = now
        } else if let raw = store.defaults?.string(forKey: AppGroupKeys.selectedDate),
                  let date = FlutterDate.parse(raw) {
            dateSelectionMode = .explicitDate
            selectedDate = date
        }
    }

    func refreshForDateBoundary() {
        guard cardStore.load(now: today) != nil else { return }
        refreshFollowingToday()
        publish()
    }

    /// Recomposes and republishes. Safe to call on every edit.
    func publish() {
        let snapshot = currentSnapshot()
        self.snapshot = snapshot
        recordCandidateCapacity(snapshot)
        store.saveDashboardState(snapshot.dictionary(isPro: entitlements.isPro))
        Task { await liveActivity.update(snapshot: snapshot, isPro: entitlements.isPro) }
    }

    /// Recomposes and waits until the running Lock Screen card receives the update.
    func updateLiveActivity() async {
        let snapshot = currentSnapshot()
        self.snapshot = snapshot
        recordCandidateCapacity(snapshot)
        store.saveDashboardState(snapshot.dictionary(isPro: entitlements.isPro))
        await liveActivity.update(snapshot: snapshot, isPro: entitlements.isPro)
    }

    private func recordCandidateCapacity(_ snapshot: DashboardSnapshot) {
        let now = nowProvider()
        let rule = lastResolvedRuleID.flatMap { id in
            (try? SmartLockScreenSchedule.load(store: store))?.rules.first { $0.id == id }
        }
        let day = snapshot.selectedDate ?? now
        let candidates = snapshot.calendarDays.first { $0.id == FlutterDate.dateKey(day, calendar: calendar) }?.todoItems.count ?? 0
        let layout = LockScreenTemplate(rawValue: snapshot.lockScreenLayout)
        let showsTodoRows = snapshot.showTodosOnLockScreen && (layout == .memoTodo || layout?.isTodoOnly == true
            || (layout == .calendarItems && snapshot.selectedContentSection == "todo"))
        let rowLimit = showsTodoRows ? (snapshot.textScale > 1.08 ? 3 : 4) : 0
        analytics?.displayCandidates(template: snapshot.lockScreenLayout, candidates: candidates,
            payloadLimit: 5, rowLimit: rowLimit, selected: rule?.todoSeriesIDs != nil, privacyRestricted: snapshot.privacyMode != "full")
    }

    /// Starts the Lock Screen card. Throws so the caller can show the real
    /// reason instead of failing silently.
    func startLiveActivity() async throws {
        let snapshot = currentSnapshot()
        self.snapshot = snapshot
        try await liveActivity.start(snapshot: snapshot, isPro: entitlements.isPro)
    }

    func stopLiveActivity() async {
        await liveActivity.end()
    }
}

/// Lets the coordinator ask about Pro without depending on StoreKit.
@MainActor
protocol EntitlementProviding: AnyObject {
    var isPro: Bool { get }
}

extension DashboardStrings {
    /// Localized strings for the composer, resolved from the app's catalog.
    static var current: DashboardStrings {
        DashboardStrings(
            noEvents: appString(localized: "dashboard.noEvents", defaultValue: "No events"),
            hiddenContent: appString(localized: "privacy.hidden", defaultValue: "Hidden"),
            checkInApp: appString(localized: "privacy.checkInApp", defaultValue: "Open the app to view"),
            dDayToday: appString(localized: "dday.today", defaultValue: "D-Day"),
            dPlusPrefix: appString(localized: "dday.plusPrefix", defaultValue: "D+"),
            timePassed: appString(localized: "countdown.passed", defaultValue: "Time passed"),
            hoursMinutesRemaining: appString(localized: "countdown.remaining", defaultValue: "left"),
            remainingTasks: appString(localized: "todo.remaining", defaultValue: "Remaining")
        )
    }
}

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

    private let cardStore: CardStore
    private let settingsStore: LockScreenSettingsStore
    private let liveActivity: LiveActivityService
    private let entitlements: EntitlementProviding
    private let store: AppGroupStore
    private let calendar: Calendar

    init(
        cardStore: CardStore,
        settingsStore: LockScreenSettingsStore,
        liveActivity: LiveActivityService,
        entitlements: EntitlementProviding,
        store: AppGroupStore = AppGroupStore(),
        calendar: Calendar = .current
    ) {
        self.cardStore = cardStore
        self.settingsStore = settingsStore
        self.liveActivity = liveActivity
        self.entitlements = entitlements
        self.store = store
        self.calendar = calendar
        let followsToday = store.defaults?.object(forKey: FlutterPreferenceKeys.followToday) as? Bool ?? true
        self.dateSelectionMode = followsToday ? .followToday : .explicitDate
        if !followsToday,
           let raw = store.defaults?.string(forKey: AppGroupKeys.selectedDate),
           let storedDate = FlutterDate.parse(raw) {
            self.selectedDate = storedDate
        } else {
            self.selectedDate = Date()
        }
    }

    var composer: DashboardComposer {
        DashboardComposer(
            strings: .current,
            calendar: calendar,
            localeIdentifier: AppLanguagePreference.resolvedLocaleIdentifier(from: store.defaults)
        )
    }

    func currentSnapshot(now: Date = Date()) -> DashboardSnapshot {
        let effectiveDate = dateSelectionMode == .followToday ? now : selectedDate
        return composer.compose(
            cards: cardStore.cards,
            selectedDate: effectiveDate,
            settings: settingsStore.settings,
            privacyMode: settingsStore.defaultPrivacyMode,
            now: now
        )
    }

    func followToday(now: Date = Date()) {
        dateSelectionMode = .followToday
        selectedDate = now
        store.defaults?.set(true, forKey: FlutterPreferenceKeys.followToday)
    }

    func selectExplicitDate(_ date: Date) {
        dateSelectionMode = .explicitDate
        selectedDate = date
        store.defaults?.set(false, forKey: FlutterPreferenceKeys.followToday)
    }

    func refreshFollowingToday(now: Date = Date()) {
        guard dateSelectionMode == .followToday else { return }
        selectedDate = now
    }

    func refreshSelectionFromSharedDefaults(now: Date = Date()) {
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

    /// Recomposes and republishes. Safe to call on every edit.
    func publish() {
        let snapshot = currentSnapshot()
        self.snapshot = snapshot
        store.saveDashboardState(snapshot.dictionary(isPro: entitlements.isPro))
        Task { await liveActivity.update(snapshot: snapshot, isPro: entitlements.isPro) }
    }

    /// Recomposes and waits until the running Lock Screen card receives the update.
    func updateLiveActivity() async {
        let snapshot = currentSnapshot()
        self.snapshot = snapshot
        store.saveDashboardState(snapshot.dictionary(isPro: entitlements.isPro))
        await liveActivity.update(snapshot: snapshot, isPro: entitlements.isPro)
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

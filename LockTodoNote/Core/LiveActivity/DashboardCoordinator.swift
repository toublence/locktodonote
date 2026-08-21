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
    @Published var selectedDate: Date = Date()
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
    }

    var composer: DashboardComposer {
        DashboardComposer(
            strings: .current,
            calendar: calendar,
            localeIdentifier: AppLanguagePreference.resolvedLocaleIdentifier(from: store.defaults)
        )
    }

    func currentSnapshot(now: Date = Date()) -> DashboardSnapshot {
        composer.compose(
            cards: cardStore.cards,
            selectedDate: selectedDate,
            settings: settingsStore.settings,
            privacyMode: settingsStore.defaultPrivacyMode,
            now: now
        )
    }

    /// Recomposes and republishes. Safe to call on every edit.
    func publish() {
        let snapshot = currentSnapshot()
        self.snapshot = snapshot
        store.saveDashboardState(snapshot.dictionary(isPro: entitlements.isPro))
        Task { await liveActivity.update(snapshot: snapshot, isPro: entitlements.isPro) }
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

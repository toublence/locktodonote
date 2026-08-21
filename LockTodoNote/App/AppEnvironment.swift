import SwiftUI
import LockTodoNoteShared

/// Wires the stores together and runs one-time launch work.
///
/// Migration happens here, synchronously, before the first view is built: a
/// view that renders an empty card list because migration had not finished yet
/// would look exactly like data loss to an upgrading user.
@MainActor
final class AppEnvironment: ObservableObject {
    let cardStore: CardStore
    let themeStore: ThemeStore
    let settingsStore: LockScreenSettingsStore
    let liveActivity: LiveActivityService
    let purchases: PurchaseService
    let analytics: AnalyticsService
    let dashboard: DashboardCoordinator
    let links: LinkStore
    let appGroup: AppGroupStore

    @Published private(set) var migrationOutcome: FlutterDataMigrator.Outcome?
    @Published var pendingDeepLink: DeepLink?
    /// Set when a review prompt has been earned; the view layer owns the
    /// actual request because `requestReview` is an environment action.
    @Published var shouldRequestReview = false
    /// Migrated users carry their completed flag across, so onboarding shows
    /// only to genuinely new installs.
    @Published var needsOnboarding: Bool = false
    /// Capture is presented from one place only. Nesting a sheet inside a tab
    /// while `TabView` also owns one means the inner sheet never appears.
    @Published var quickAddRequest: QuickAddRequest?
    @Published var paywallRequest: PaywallRequest?

    /// UI tests need a predictable starting point. Guarded by a launch
    /// argument so it can never fire in a shipped build.
    static let uiTestResetArgument = "-uitest-reset"
    static let uiTestSkipOnboardingArgument = "-uitest-skip-onboarding"

    init(appGroup: AppGroupStore = AppGroupStore()) {
        self.appGroup = appGroup
        Self.resetForUITestsIfRequested(appGroup: appGroup)
        let outcome = FlutterDataMigrator(store: appGroup)?.migrateIfNeeded()
        self.migrationOutcome = outcome

        let cardStore = CardStore()
        let settingsStore = LockScreenSettingsStore(store: appGroup)
        let liveActivity = LiveActivityService(store: appGroup)
        let purchases = PurchaseService(store: appGroup)
        let analytics = AnalyticsService(store: appGroup)

        self.cardStore = cardStore
        self.themeStore = ThemeStore(store: appGroup)
        self.settingsStore = settingsStore
        self.liveActivity = liveActivity
        self.purchases = purchases
        self.analytics = analytics
        self.links = LinkStore(store: appGroup)
        self.dashboard = DashboardCoordinator(
            cardStore: cardStore,
            settingsStore: settingsStore,
            liveActivity: liveActivity,
            entitlements: purchases,
            store: appGroup
        )

        cardStore.load()
        // Any edit anywhere republishes the Lock Screen.
        cardStore.onChange = { [weak self] in self?.dashboard.publish() }
        settingsStore.onChange = { [weak self] in self?.dashboard.publish() }
        analytics.record(migration: outcome)

        let defaults = appGroup.defaults
        let completed = defaults?.bool(forKey: FlutterPreferenceKeys.hasCompletedOnboarding) ?? false
        // Someone who already has cards has clearly used the app before, even
        // if the flag never got written.
        self.needsOnboarding = !completed && cardStore.cards.isEmpty
    }

    private static func resetForUITestsIfRequested(appGroup: AppGroupStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(uiTestResetArgument) else { return }

        if let url = appGroup.cardStoreURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let defaults = appGroup.defaults {
            for key in defaults.dictionaryRepresentation().keys {
                defaults.removeObject(forKey: key)
            }
            if arguments.contains(uiTestSkipOnboardingArgument) {
                defaults.set(true, forKey: FlutterPreferenceKeys.hasCompletedOnboarding)
            }
        }
    }

    func completeOnboarding() {
        appGroup.defaults?.set(true, forKey: FlutterPreferenceKeys.hasCompletedOnboarding)
        needsOnboarding = false
        dashboard.publish()
    }

    private let triggers = MonetizationTriggers()

    func bootstrap() async {
        analytics.ensureInstallDate()
        await purchases.refreshEntitlement()
        analytics.isPremium = purchases.isPro
        await purchases.loadProducts()
        dashboard.publish()
        analytics.flushQueuedEvents()
        checkLapsedTrialPaywall()
        checkDayTwoPaywall()
    }

    /// The first time a card actually reaches the Lock Screen. This is the one
    /// moment the app has proven its value, so it is where the upgrade ask
    /// belongs — and where the review prompt is genuinely earned.
    func offerPaywallAfterFirstLockScreenSuccess() async {
        analytics.tryCompleteActivation()
        guard !purchases.isPro else {
            requestReviewIfEarned()
            return
        }
        guard triggers.claimFirstLockScreenSuccess() else {
            requestReviewIfEarned()
            return
        }
        requestPaywall(source: "first_lock_screen_success")
    }

    /// The 24-hour preview lapsed — the user just lost a template they used.
    func checkLapsedTrialPaywall() {
        purchases.refreshTrialState()
        guard !purchases.isPro, triggers.claimTrialExpired() else { return }
        requestPaywall(source: "trial_expired")
    }

    func checkDayTwoPaywall() {
        guard
            !purchases.isPro,
            analytics.hasCompletedActivation,
            triggers.claimDayTwo()
        else { return }
        requestPaywall(source: "day_2_soft_hint")
    }

    /// Called when a Shortcut capture is refused by the free daily limit.
    func offerPaywallForShortcutLimit() {
        guard !purchases.isPro else { return }
        requestPaywall(source: "shortcut_limit_reached")
    }

    func requestReviewIfEarned() {
        guard triggers.claimReviewRequest() else { return }
        analytics.reviewRequested()
        shouldRequestReview = true
    }

    /// Installing the widget earns a fresh 24-hour Pro window, and re-arms the
    /// prompt for when that window closes.
    func grantWidgetInstallRewardIfNeeded() {
        guard triggers.claimWidgetInstallReward() else { return }
        guard !purchases.isPro else { return }
        purchases.grantWidgetInstallTrial()
        triggers.rearmTrialExpiredPrompt()
        analytics.temporaryTrialStarted(source: "widget_install")
    }

    /// Re-reads the card file and drains extension queues. Called on every
    /// foreground because intents mutate shared state while the app is away.
    func refreshFromBackgroundWork() {
        let result = cardStore.load()
        settingsStore.refreshFromSharedDefaults()
        purchases.refreshTrialState()
        liveActivity.refreshState()
        analytics.flushQueuedEvents()
        // Drains the share extension's queue so it cannot grow unbounded.
        links.load()

        if let result {
            for completion in result.mergedCompletions {
                analytics.todoCompletedFromExtension(source: completion.source)
            }
            if !result.mergedQuickAdds.isEmpty {
                analytics.shortcutQuickAddsMerged(count: result.mergedQuickAdds.count)
            }
        }
        dashboard.publish()
        Task { await purchases.refreshEntitlement() }
    }

    func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        pendingDeepLink = link
        if let source = link.source {
            analytics.openedApp(from: source)
        }
    }

    func requestQuickAdd(_ mode: QuickAddMode, date: Date = Date(), source: String = "app") {
        quickAddRequest = QuickAddRequest(mode: mode, date: date, source: source)
    }

    /// Shows the paywall. `source` becomes the `paywall_trigger` parameter, so
    /// the values must stay stable for the existing funnel.
    func requestPaywall(source: String) {
        analytics.paywallSeen(source: source)
        paywallRequest = PaywallRequest(source: source)
    }
}

struct QuickAddRequest: Identifiable, Equatable {
    let mode: QuickAddMode
    let date: Date
    let source: String

    var id: String { "\(mode.rawValue)-\(source)-\(date.timeIntervalSince1970)" }
}

struct PaywallRequest: Identifiable, Equatable {
    let source: String
    var id: String { source }
}

/// Observable wrapper around the Lock Screen settings stored in the App Group.
@MainActor
final class LockScreenSettingsStore: ObservableObject {
    @Published var settings: LockScreenSettings {
        didSet {
            guard let defaults else { return }
            settings.save(to: defaults)
            onChange?()
        }
    }

    @Published var defaultPrivacyMode: PrivacyMode {
        didSet {
            defaults?.set(defaultPrivacyMode.rawValue, forKey: FlutterPreferenceKeys.defaultPrivacyMode)
            onChange?()
        }
    }

    var onChange: (@MainActor () -> Void)?

    private let defaults: UserDefaults?

    init(store: AppGroupStore = AppGroupStore()) {
        let defaults = store.defaults
        self.defaults = defaults
        self.settings = defaults.map(LockScreenSettings.load(from:)) ?? LockScreenSettings()
        self.defaultPrivacyMode = PrivacyMode(
            fromStored: defaults?.string(forKey: FlutterPreferenceKeys.defaultPrivacyMode)
        )
    }

    func refreshFromSharedDefaults() {
        guard let defaults else { return }
        let refreshed = LockScreenSettings.load(from: defaults)
        guard refreshed != settings else { return }
        settings = refreshed
    }
}

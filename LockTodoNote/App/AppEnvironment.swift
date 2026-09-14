import SwiftUI
import StoreKit
import WidgetKit
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
    let notifications: NotificationService
    let reviewCoordinator: ReviewRequestCoordinator
    let dashboard: DashboardCoordinator
    let links: LinkStore
    let appGroup: AppGroupStore

    @Published private(set) var migrationOutcome: FlutterDataMigrator.Outcome?
    @Published var pendingDeepLink: DeepLink?
    /// Migrated users carry their completed flag across, so onboarding shows
    /// only to genuinely new installs.
    @Published var needsOnboarding: Bool = false
    /// Capture is presented from one place only. Nesting a sheet inside a tab
    /// while `TabView` also owns one means the inner sheet never appears.
    @Published var quickAddRequest: QuickAddRequest?
    @Published var paywallRequest: PaywallRequest?
    @Published var showShortcutLimitPrompt = false
    @Published var isProInfoPresented = false
    @Published var memoEditorRequest: Card?
    @Published var deepLinkError: String?
    @Published var showReminderSuggestion = false
    @Published private(set) var isWidgetInstalled = false
    private(set) var pendingProPreview: ProPreviewDraft?
    private var pendingPurchaseContext: PendingPurchaseContext?
    private var latestEntrySource = "app"
    private static let pendingPurchaseKey = "locktodonote.purchase.pending_context.v2"

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
        let notifications = NotificationService(store: appGroup)
        let reviewCoordinator = ReviewRequestCoordinator(store: appGroup)

        self.cardStore = cardStore
        self.themeStore = ThemeStore(store: appGroup)
        self.settingsStore = settingsStore
        self.liveActivity = liveActivity
        self.purchases = purchases
        self.analytics = analytics
        self.notifications = notifications
        self.reviewCoordinator = reviewCoordinator
        self.links = LinkStore(store: appGroup)
        self.dashboard = DashboardCoordinator(
            cardStore: cardStore,
            settingsStore: settingsStore,
            liveActivity: liveActivity,
            entitlements: purchases,
            store: appGroup
        )
        reviewCoordinator.attachAnalytics(analytics)
        analytics.reviewCoordinator = reviewCoordinator
        notifications.attachAnalytics(analytics)
        purchases.onEntitlementChanged = { [weak self] entitlement, transaction in
            guard let self else { return }
            Task { @MainActor in
                await self.entitlementDidChange(entitlement, transaction: transaction)
            }
        }

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
        if let data = defaults?.data(forKey: Self.pendingPurchaseKey),
           let envelope = try? JSONDecoder().decode(PendingPurchaseEnvelope.self, from: data) {
            pendingPurchaseContext = envelope.context
            pendingProPreview = envelope.preview?.draft(snapshot: dashboard.currentSnapshot())
        }
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
        if !cardStore.cards.isEmpty {
            Task { await ensureLiveActivityStarted(reason: "onboarding_complete") }
        }
        offerReminderSuggestionIfEligible()
    }

    private let triggers = MonetizationTriggers()

    func bootstrap() async {
        analytics.ensureInstallDate()
        reviewCoordinator.recordUsageDay()
        await purchases.refreshEntitlement()
        analytics.isPremium = purchases.isPro
        enforceTemplateEntitlement(purchases.entitlement)
        await purchases.loadProducts()
        dashboard.refreshSelectionFromSharedDefaults()
        dashboard.publish()
        if !needsOnboarding {
            await ensureLiveActivityStarted()
        }
        analytics.flushQueuedEvents()
        analytics.appReturned(
            entrySource: latestEntrySource,
            activityState: liveActivity.state.analyticsName,
            hasTodayContent: hasContent(on: Date())
        )
        recordStaleActivityIfNeeded()
        checkLapsedTrialPaywall()
        consumeShortcutLimitSignal()
    }

    /// The first time a card actually reaches the Lock Screen. This is the one
    /// moment the app has proven its value, so it is where the upgrade ask
    /// belongs — and where the review prompt is genuinely earned.
    func offerPaywallAfterFirstLockScreenSuccess() async {
        analytics.tryCompleteActivation()
        offerReminderSuggestionIfEligible()
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

    /// Called when a Shortcut capture is refused by the free daily limit.
    func offerPaywallForShortcutLimit() {
        guard !purchases.isPro else { return }
        requestPaywall(source: "shortcut_limit_reached")
    }

    func requestReviewIfEarned() {
        reviewCoordinator.evaluate(trigger: "live_activity_success")
    }

    /// Today should already be on the Lock Screen when the user opens the app.
    /// Failures remain non-blocking; the Today status card still explains how
    /// to enable Live Activities if iOS has disabled them.
    func ensureLiveActivityStarted(reason: String = "cold_launch") async {
        liveActivity.refreshState()
        guard !liveActivity.state.isRunning else { return }
        guard !(appGroup.defaults?.bool(forKey: FlutterPreferenceKeys.explicitlyStoppedLiveActivity) ?? false) else {
            return
        }
        let snapshot = dashboard.currentSnapshot()
        guard !snapshot.todoItems.isEmpty || !snapshot.memoItems.isEmpty else { return }
        let requestId = UUID().uuidString
        analytics.liveActivityStartAttempt(
            requestId: requestId,
            source: "automatic",
            templateId: settingsStore.settings.template.rawValue,
            reason: reason
        )
        do {
            try await dashboard.startLiveActivity()
            let todos = cardStore.todoCards(on: Date()).flatMap(\.checklistItems)
            analytics.liveActivityStarted(
                taskCount: todos.count,
                remainingCount: todos.filter { !$0.isDone }.count,
                hasMemo: cardStore.pinnedMemo != nil,
                templateId: settingsStore.settings.template.rawValue,
                source: "automatic",
                requestId: requestId
            )
        } catch let error as LiveActivityService.LiveActivityError {
            analytics.liveActivityStartFailed(
                reason: error.analyticsReason,
                templateId: settingsStore.settings.template.rawValue,
                source: "automatic",
                requestId: requestId
            )
        } catch {
            analytics.liveActivityStartFailed(
                reason: "automatic_start_failed",
                templateId: settingsStore.settings.template.rawValue,
                source: "automatic",
                requestId: requestId
            )
        }
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

    @discardableResult
    func verifyWidgetInstallation() async -> Bool {
        let installed = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let found = (try? result.get())?.contains { $0.kind == AppGroupKeys.widgetKind } ?? false
                continuation.resume(returning: found)
            }
        }
        isWidgetInstalled = installed
        guard installed else { return false }
        let wasConfirmed = appGroup.defaults?.bool(forKey: AppGroupKeys.widgetInstallationConfirmed) ?? false
        appGroup.defaults?.set(true, forKey: AppGroupKeys.widgetInstallationConfirmed)
        appGroup.defaults?.removeObject(forKey: AppGroupKeys.widgetConfirmationPending)
        if !wasConfirmed {
            analytics.widgetInstalledConfirmed(method: "os_configuration")
        }
        grantWidgetInstallRewardIfNeeded()
        offerReminderSuggestionIfEligible()
        return true
    }

    /// Re-reads the card file and drains extension queues. Called on every
    /// foreground because intents mutate shared state while the app is away.
    func refreshFromBackgroundWork() {
        reviewCoordinator.recordUsageDay()
        let result = cardStore.load()
        dashboard.refreshSelectionFromSharedDefaults()
        settingsStore.refreshFromSharedDefaults()
        purchases.refreshTrialState()
        liveActivity.refreshState()
        recordStaleActivityIfNeeded()
        analytics.flushQueuedEvents()
        // Drains the share extension's queue so it cannot grow unbounded.
        links.load()

        _ = result
        dashboard.publish()
        analytics.appReturned(
            entrySource: latestEntrySource,
            activityState: liveActivity.state.analyticsName,
            hasTodayContent: hasContent(on: Date())
        )
        latestEntrySource = "app"
        Task {
            await purchases.refreshEntitlement()
            liveActivity.refreshState()
            if liveActivity.state.recoveryRequired {
                await ensureLiveActivityStarted(reason: "foreground_recovery")
            }
        }
        consumeShortcutLimitSignal()
    }

    private func recordStaleActivityIfNeeded() {
        guard case .possiblyExpired = liveActivity.state else { return }
        guard !(appGroup.defaults?.bool(forKey: AppGroupKeys.liveActivityStaleLogged) ?? false) else { return }
        appGroup.defaults?.set(true, forKey: AppGroupKeys.liveActivityStaleLogged)
        analytics.liveActivityBecameStale()
    }

    func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        pendingDeepLink = link
        if let source = link.source {
            latestEntrySource = source
            analytics.openedApp(from: source)
        }
    }

    func openCard(id: String) {
        guard let card = cardStore.card(id: id) else {
            deepLinkError = appString(
                localized: "deeplink.cardMissing",
                defaultValue: "That item is no longer available."
            )
            return
        }
        dashboard.selectExplicitDate(card.targetDateTime ?? card.createdAt)
        if card.type == .quickNote {
            memoEditorRequest = card
        }
    }

    func enableSuggestedReminder(morning: Bool) async {
        let kind = morning ? "morning" : "evening"
        analytics.reminderAction("accepted", kind: kind, source: "activation")
        let granted = await notifications.requestAuthorization()
        analytics.reminderAction(granted ? "permission_granted" : "permission_denied", kind: kind, source: "activation")
        guard granted else { return }
        if morning {
            notifications.settings.morningEnabled = true
        } else {
            notifications.settings.eveningEnabled = true
        }
        analytics.reminderAction("enabled", kind: kind, source: "activation")
    }

    func dismissReminderSuggestion() {
        analytics.reminderAction("dismissed", kind: "none", source: "activation")
    }

    private func offerReminderSuggestionIfEligible() {
        guard analytics.hasCompletedActivation,
              appGroup.defaults?.bool(forKey: FlutterPreferenceKeys.reminderSuggestionShown) != true
        else { return }
        appGroup.defaults?.set(true, forKey: FlutterPreferenceKeys.reminderSuggestionShown)
        analytics.reminderAction("suggested", kind: "morning_or_evening", source: "activation")
        showReminderSuggestion = true
    }

    func requestQuickAdd(_ mode: QuickAddMode, date: Date = Date(), source: String = "app") {
        quickAddRequest = QuickAddRequest(mode: mode, date: date, source: source)
    }

    /// Shows the paywall. `source` becomes the `paywall_trigger` parameter, so
    /// the values must stay stable for the existing funnel.
    func requestPaywall(source: String, preview: ProPreviewDraft? = nil) {
        pendingProPreview = preview
        paywallRequest = PaywallRequest(source: source)
    }

    func registerPendingPurchase(
        productId: String,
        source: String,
        price: Decimal?,
        currency: String?,
        isTrial: Bool,
        previewTemplate: String?,
        attemptId: String
    ) {
        pendingPurchaseContext = PendingPurchaseContext(
            productId: productId,
            source: source,
            price: price,
            currency: currency,
            isTrial: isTrial,
            previewTemplate: previewTemplate,
            attemptId: attemptId
        )
        persistPendingPurchase()
    }

    private func entitlementDidChange(
        _ entitlement: Entitlement,
        transaction: StoreKit.Transaction?
    ) async {
        analytics.isPremium = entitlement.isPro
        analytics.trialType = entitlement.temporaryTrialActive ? "temporary_pro_24h" : "none"
        enforceTemplateEntitlement(entitlement)
        dashboard.publish()
        guard entitlement.isPro, let context = pendingPurchaseContext else { return }
        analytics.purchaseCompleted(
            productId: transaction?.productID ?? context.productId,
            source: context.source,
            price: context.price,
            currency: context.currency,
            isTrial: context.isTrial,
            previewTemplate: context.previewTemplate,
            attemptId: context.attemptId
        )
        let application = await applyPendingProValue()
        if application.valueApplied, context.previewTemplate != nil {
            analytics.purchaseValueApplied(
                productId: context.productId,
                source: context.source,
                price: context.price,
                currency: context.currency,
                isTrial: context.isTrial,
                previewTemplate: context.previewTemplate,
                attemptId: context.attemptId
            )
        }
        pendingPurchaseContext = nil
        appGroup.defaults?.removeObject(forKey: Self.pendingPurchaseKey)
    }

    private func enforceTemplateEntitlement(_ entitlement: Entitlement) {
        guard let feature = settingsStore.settings.template.proFeature,
              !entitlement.canUse(feature)
        else { return }
        settingsStore.settings.template = .default
    }

    @discardableResult
    func applyPendingProValue() async -> ProValueApplicationResult {
        guard let draft = pendingProPreview else { return .nothingToApply }
        let resolved = draft.template.resolvedTemplate(
            for: settingsStore.settings.selectedContentSection
        )
        if let imageData = draft.imageData {
            do {
                let imageStore = LockScreenImageStore(store: appGroup)
                let fileName = try imageStore.save(
                    imageData: imageData,
                    replacing: nil
                )
                if resolved == .imageTodo {
                    settingsStore.settings.imageTodoFileName = fileName
                } else if resolved == .imageMemo {
                    settingsStore.settings.imageMemoFileName = fileName
                }
                settingsStore.settings.imageFileName = fileName
            } catch {
                return .failed(reason: "image_save_failed")
            }
        }
        if resolved == .ddayMemo {
            settingsStore.settings.ddayTitle = draft.ddayTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            settingsStore.settings.ddayTargetDate = draft.ddayDate
            settingsStore.settings.ddayMemo = draft.ddayMemo?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        settingsStore.settings.template = resolved
        analytics.templateChanged(resolved.rawValue)
        dashboard.publish()
        var liveActivityResult = "already_active"
        if !liveActivity.state.isRunning {
            do {
                try await dashboard.startLiveActivity()
                liveActivityResult = "started"
            } catch {
                liveActivityResult = "start_failed"
            }
        }
        pendingProPreview = nil
        return .applied(liveActivityResult: liveActivityResult)
    }

    func clearPendingProPreview() {
        pendingProPreview = nil
    }

    private func persistPendingPurchase() {
        guard let context = pendingPurchaseContext,
              let data = try? JSONEncoder().encode(
                PendingPurchaseEnvelope(context: context, preview: pendingProPreview)
              )
        else { return }
        appGroup.defaults?.set(data, forKey: Self.pendingPurchaseKey)
    }

    private func consumeShortcutLimitSignal() {
        guard !purchases.isPro,
              appGroup.defaults?.bool(forKey: AppGroupKeys.shortcutLimitReached) == true
        else { return }
        appGroup.defaults?.set(false, forKey: AppGroupKeys.shortcutLimitReached)
        showShortcutLimitPrompt = true
    }

    private func hasContent(on date: Date) -> Bool {
        !cardStore.todoCards(on: date).isEmpty || !cardStore.memoCards(on: date).isEmpty
    }
}

struct ProPreviewDraft: Hashable {
    let template: LockScreenTemplate
    let snapshot: DashboardSnapshot
    let imageData: Data?
    let ddayTitle: String?
    let ddayDate: Date?
    let ddayMemo: String?
}

private struct PendingPurchaseContext: Codable {
    let productId: String
    let source: String
    let price: Decimal?
    let currency: String?
    let isTrial: Bool
    let previewTemplate: String?
    let attemptId: String
}

private struct PendingPurchaseEnvelope: Codable {
    let context: PendingPurchaseContext
    let preview: PersistedProPreview?

    init(context: PendingPurchaseContext, preview: ProPreviewDraft?) {
        self.context = context
        self.preview = preview.map(PersistedProPreview.init)
    }
}

private struct PersistedProPreview: Codable {
    let template: LockScreenTemplate
    let imageData: Data?
    let ddayTitle: String?
    let ddayDate: Date?
    let ddayMemo: String?

    init(_ draft: ProPreviewDraft) {
        template = draft.template
        imageData = draft.imageData
        ddayTitle = draft.ddayTitle
        ddayDate = draft.ddayDate
        ddayMemo = draft.ddayMemo
    }

    func draft(snapshot: DashboardSnapshot) -> ProPreviewDraft {
        ProPreviewDraft(
            template: template,
            snapshot: snapshot,
            imageData: imageData,
            ddayTitle: ddayTitle,
            ddayDate: ddayDate,
            ddayMemo: ddayMemo
        )
    }
}

enum ProValueApplicationResult: Equatable {
    case nothingToApply
    case applied(liveActivityResult: String)
    case failed(reason: String)

    var valueApplied: Bool {
        if case .applied = self { return true }
        return false
    }

    var succeeded: Bool {
        switch self {
        case .nothingToApply, .applied: true
        case .failed: false
        }
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
        self.settings = Self.normalized(
            defaults.map(LockScreenSettings.load(from:)) ?? LockScreenSettings()
        )
        self.defaultPrivacyMode = PrivacyMode(
            fromStored: defaults?.string(forKey: FlutterPreferenceKeys.defaultPrivacyMode)
        )
        if let defaults {
            self.settings.save(to: defaults)
        }
    }

    func refreshFromSharedDefaults() {
        guard let defaults else { return }
        let refreshed = Self.normalized(LockScreenSettings.load(from: defaults))
        guard refreshed != settings else { return }
        settings = refreshed
    }

    /// Content and date selection are controlled from Today/Calendar. Keeping
    /// hidden legacy switches would let old values make the chosen content disappear.
    private static func normalized(_ stored: LockScreenSettings) -> LockScreenSettings {
        var settings = stored
        settings.showTodos = true
        settings.showMemos = true
        settings.showCompletedTodos = false
        settings.syncCalendarSelectionToLockScreen = true
        return settings
    }
}

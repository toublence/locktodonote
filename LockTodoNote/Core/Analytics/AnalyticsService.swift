import Foundation
import LockTodoNoteShared

/// Where events actually go. Swapping the backend never touches call sites,
/// and tests can assert on a recorder without Firebase in the loop.
protocol AnalyticsBackend: AnyObject {
    var isEnabled: Bool { get }
    func log(name: String, parameters: [String: Any])
}

/// Event names and parameters are carried over from the Flutter build verbatim.
/// Renaming any of them would split the existing dashboards in two, so new
/// behaviour gets new events rather than renamed ones.
@MainActor
final class AnalyticsService: ObservableObject {
    private let backend: AnalyticsBackend
    private let store: AppGroupStore
    private let defaults: UserDefaults?
    weak var reviewCoordinator: ReviewRequestCoordinator?

    init(store: AppGroupStore = AppGroupStore(), backend: AnalyticsBackend? = nil) {
        self.store = store
        self.defaults = store.defaults
        self.backend = backend ?? FirebaseAnalyticsBackend()
    }

    // MARK: - Core logging

    /// Parameters every event carries, matching the Flutter payload.
    private var commonParameters: [String: Any] {
        let locale = Locale.current
        var parameters: [String: Any] = [
            "analytics_schema_version": 2,
            "analytics_release": "L1.2.2",
            "telemetry_environment": Self.telemetryEnvironment,
            "app_build": AppInfo.build,
            "implementation": "swiftui",
            "days_since_install": daysSinceInstall,
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "is_premium": isPremium ? 1 : 0,
            "trial_type": trialType,
            "ios_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "device_family": "ios",
        ]
        parameters["language"] = locale.language.languageCode?.identifier ?? "unknown"
        parameters["widget_configuration_state"] = defaults?.string(forKey: "analytics.widget.configuration.state") ?? "unknown"
        if let region = locale.region?.identifier {
            parameters["country"] = region
        }
        return parameters
    }

    var isPremium = false
    var trialType = "none"

    static var telemetryEnvironment: String {
        #if DEBUG
        return "debug"
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "sandbox" : "release_unknown"
        #endif
    }

    private func log(_ name: String, _ parameters: [String: Any] = [:]) {
        let common = commonParameters
        // Firebase accepts only 25 parameters. Event-specific fields take
        // precedence over optional legacy device context, never release identity.
        var merged = parameters
        if merged["occurred_at_ms"] == nil { merged["occurred_at_ms"] = Int64(Date().timeIntervalSince1970 * 1000) }
        let allowedSources: Set<String> = ["app", "inline", "calendar", "onboarding", "live_activity", "dynamic_island", "widget", "shortcut", "intent", "siri", "action_button", "unknown", "settings", "paywall", "display", "top_control", "today_tab", "automatic", "automatic_sync", "os_configuration", "candidate_calculation", "queue_merge", "activation", "memo_editor", "todo_editor", "notification"]
        for key in ["source", "entry_source", "surface", "action_origin"] {
            if let value = merged[key] as? String, !allowedSources.contains(value) { merged[key] = "unknown" }
        }
        for key in ["analytics_release", "app_version", "app_build", "analytics_schema_version", "telemetry_environment"] {
            merged[key] = common[key]
        }
        for key in ["is_premium", "trial_type", "days_since_install", "implementation", "device_family", "language", "widget_configuration_state", "country", "ios_version"] where merged.count < 25 {
            if merged[key] == nil { merged[key] = common[key] }
        }
        // Redundant legacy aliases are lowest priority when an old event is full.
        for key in ["quoted_price", "price", "completed_count", "screen_name", "setup_type", "ios_version", "device_family", "live_activity_enabled", "is_pro", "target", "selected_template"] where merged.count > 25 {
            merged.removeValue(forKey: key)
        }
        // Protect the wire contract even if a future call site adds too much.
        let required: Set<String> = ["analytics_release", "app_version", "app_build", "analytics_schema_version", "telemetry_environment", "source", "result", "event_id", "occurred_at_ms", "forwarded_at_ms", "origin_app_version", "origin_app_build", "origin_release", "origin_environment", "storage_stage", "attempt_id", "request_id", "capture_id", "transaction_environment", "transaction_trial_state", "trial_basis", "value_basis", "is_revenue_event"]
        for key in merged.keys.sorted() where merged.count > 25 && !required.contains(key) {
            merged.removeValue(forKey: key)
        }
        for (key, value) in merged {
            merged[key] = (value as? Bool).map { $0 ? 1 : 0 } ?? value
        }
        backend.log(name: name, parameters: merged)
        reviewCoordinator?.record(event: name, parameters: merged)
    }

    /// Only finite, product-defined values reach new instrumentation.
    enum Feature: String { case automaticSwitching = "automatic_switching", reminders, repeatRule = "repeat", layoutShortcut = "layout_shortcut" }
    enum Outcome: String { case opened, attempted, success, failed, cancelled, enabled, disabled }
    func feature(_ feature: Feature, outcome: Outcome, count: Int? = nil) {
        var parameters: [String: Any] = ["feature": feature.rawValue, "result": outcome.rawValue, "source": "settings"]
        if let count { parameters["count_bucket"] = Self.countBucket(count) }
        log("l122_feature_action", parameters)
    }

    static func countBucket(_ count: Int) -> String {
        switch count { case ...0: "0"; case 1: "1"; case 2...5: "2_5"; case 6...10: "6_10"; case 11...30: "11_30"; default: "31_plus" }
    }

    private struct CaptureSession { let started: Date; let type: String; let id: String }
    private var captures: [String: CaptureSession] = [:]
    func captureStarted(type: String, source: String) {
        guard captures[source] == nil else { return }
        let session = CaptureSession(started: Date(), type: type, id: UUID().uuidString)
        captures[source] = session
        log("l122_capture", ["source": source, "type": type, "result": "started", "capture_id": session.id])
    }

    func captureEnded(source: String, result: String) {
        guard let session = captures.removeValue(forKey: source) else { return }
        let seconds = max(0, Date().timeIntervalSince(session.started))
        let bucket = seconds < 10 ? "under_10s" : seconds < 30 ? "10_29s" : seconds < 120 ? "30_119s" : "120s_plus"
        log("l122_capture", ["source": source, "type": session.type, "result": result,
                             "duration_bucket": bucket, "capture_id": session.id])
    }

    func memoCaptureDisplayed(selected: Bool, unchanged: Bool, ruleRestricted: Bool, replaced: Bool = false) {
        log("l122_memo_display", ["source": "inline", "selected_for_display": selected,
                                 "display_settings_unchanged": unchanged, "rule_restricted": ruleRestricted,
                                 "replaced_existing": replaced, "result": "success"])
    }

    func contentMutation(action: String, type: String, recurring: Bool = false, linked: Bool = false, selected: Bool = false) {
        log("l122_content_mutation", ["source": "app", "action": action, "type": type,
                                     "recurring": recurring, "reminder_linked": linked, "selected_for_display": selected, "result": "success"])
    }

    private var lastDisplaySignature: String?
    func displayCandidates(template: String, candidates: Int, payloadLimit: Int, rowLimit: Int, selected: Bool, privacyRestricted: Bool) {
        var parameters: [String: Any] = ["source": "candidate_calculation", "template_id": template,
            "candidate_bucket": privacyRestricted ? "unknown" : Self.countBucket(candidates),
            "capacity_bucket": Self.countBucket(rowLimit), "payload_capacity": payloadLimit,
            "selection_mode": selected ? "selected" : "all", "surface": "live_activity",
            "measurement": "render_code_upper_bound", "privacy_restricted": privacyRestricted]
        if !privacyRestricted { parameters["overflow"] = candidates > rowLimit }
        let signature = "\(template)|\(Self.countBucket(candidates))|\(payloadLimit)|\(rowLimit)|\(selected)|\(privacyRestricted)|\(candidates > rowLimit)"
        guard signature != lastDisplaySignature else { return }
        lastDisplaySignature = signature
        log("l122_display_overflow", parameters)
    }

    private var lastReminderImportBucket: String?
    func reminderImport(count: Int) {
        let bucket = Self.countBucket(count)
        guard bucket != lastReminderImportBucket else { return }
        lastReminderImportBucket = bucket
        log("l122_reminder_import", ["source": "automatic_sync", "count_bucket": Self.countBucket(count), "result": "success"])
    }

    func newTodoScope(total: Int, included: Int, selected: Bool) {
        log("l122_new_item_scope", ["source": "app", "candidate_bucket": Self.countBucket(total),
            "included_bucket": Self.countBucket(included), "selection_mode": selected ? "selected" : "all",
            "measurement": "rule_scope_not_impression", "result": "success"])
    }

    func displaySelection(todoCount: Int?, memoCount: Int?) {
        log("l122_display_selection", ["source": "settings", "todo_mode": todoCount == nil ? "all" : "selected",
            "memo_mode": memoCount == nil ? "all" : "selected", "todo_bucket": Self.countBucket(todoCount ?? 0),
            "memo_bucket": Self.countBucket(memoCount ?? 0), "result": "success"])
    }

    private var daysSinceInstall: Int {
        guard
            let stored = defaults?.string(forKey: FlutterPreferenceKeys.installDate),
            let installed = FlutterDate.parse(stored)
        else { return 0 }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: installed),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
    }

    /// Anchors retention math. Written once, on the first launch that lacks it.
    func ensureInstallDate() {
        if defaults?.string(forKey: "analytics.release_cohort") == nil {
            let existing = defaults?.string(forKey: FlutterPreferenceKeys.installDate) != nil
                || defaults?.bool(forKey: FlutterPreferenceKeys.firstTodoCreated) == true
                || defaults?.bool(forKey: FlutterPreferenceKeys.firstMemoCreated) == true
            defaults?.set(existing ? "existing_or_unknown" : "new_observed", forKey: "analytics.release_cohort")
        }
        if defaults?.string(forKey: FlutterPreferenceKeys.installDate) == nil {
            defaults?.set(FlutterDate.utcString(from: Date()), forKey: FlutterPreferenceKeys.installDate)
        }
        // An SDK app/stream change can emit first_open again for an existing
        // install. Preserve the local cohort instead of calling it a new user.
        let releaseKey = "analytics.release_observed.L1.2.2"
        if let defaults, !defaults.bool(forKey: releaseKey), backend.isEnabled {
            log("l122_release_observed", ["cohort": defaults.string(forKey: "analytics.release_cohort") ?? "unknown",
                "source": "app", "result": "success"])
            defaults.set(true, forKey: releaseKey)
        }
    }

    // MARK: - Onboarding funnel

    /// One event, not two. An earlier pass also emitted `onboarding_started`,
    /// which double-counted every start and did not match `onboarding_complete`.
    /// The Flutter build's name is the one the dashboards already hold.
    func onboardingStart() {
        log("onboarding_start", ["source": "app", "result": "success"])
    }

    func onboardingStepViewed(step: String, index: Int) {
        log("onboarding_step_view", ["source": "app", "result": "success", "step": step, "step_index": index])
    }

    func onboardingComplete(skipped: Bool) {
        log("onboarding_complete", ["source": "app", "result": "success", "skipped": skipped])
    }

    // MARK: - Quick Add & Shortcuts

    func quickAddInvoked(source: String, selectedTemplate: String, isPro: Bool) {
        log("quick_add_invoked", [
            "source": source,
            "selected_template": selectedTemplate,
            "is_pro": isPro,
            "result": "success",
        ])
    }

    func quickAddTypeSelected(type: String, source: String) {
        log("quick_add_type_selected", [
            "type": type,
            "source": source,
            "result": "success",
        ])
    }

    func shortcutQuickAdd(
        type: String,
        itemCount: Int,
        source: String,
        selectedTemplate: String,
        isPro: Bool
    ) {
        log("shortcut_quick_add", [
            "type": type,
            "target": type,
            "item_count": itemCount,
            "source": source,
            "selected_template": selectedTemplate,
            "template_id": selectedTemplate,
            "is_pro": isPro,
            "is_premium": isPro,
            "result": "success",
        ])
    }

    func quickAddFailed(reason: String, source: String) {
        log("quick_add_failed", [
            "reason": reason,
            "source": source,
            "result": "fail",
        ])
    }

    func quickAddLimitReached(dailyCount: Int, source: String) {
        log("quick_add_limit_reached", [
            "daily_count": dailyCount,
            "source": source,
            "result": "limit_reached",
        ])
    }

    func quickAddOnboardingSeen() {
        log("quick_add_onboarding_seen", [
            "source": "onboarding",
            "result": "success",
        ])
    }

    func quickAddOnboardingCTA() {
        log("quick_add_onboarding_cta", [
            "source": "onboarding",
            "result": "success",
        ])
    }

    func quickAddTipSeen() {
        log("quick_add_tip_seen", [
            "source": "today_tab",
            "result": "success",
        ])
    }

    func quickAddTipTapped() {
        log("quick_add_tip_tapped", [
            "source": "today_tab",
            "result": "success",
        ])
    }

    func quickAddEducationCompleted(source: String = "app") {
        defaults?.set(true, forKey: AppGroupKeys.quickAddEducationCompleted)
        log("quick_add_education_completed", [
            "source": source,
            "result": "success",
        ])
    }

    func lockscreenPreviewSeen(templateId: String, todoCount: Int, source: String = "onboarding") {
        defaults?.set(true, forKey: FlutterPreferenceKeys.lockscreenPreviewSeen)
        log("lockscreen_preview_seen", [
            "source": source,
            "screen_name": "activation_preview",
            "template_id": templateId,
            "todo_count": todoCount,
            "preview_type": "lockscreen_mock",
            "result": "success",
        ])
    }

    // MARK: - Activation

    func todoCreated(
        taskCount: Int,
        remainingCount: Int,
        hasMemo: Bool,
        templateId: String,
        source: String = "app",
        createdCount: Int = 1
    ) {
        captureEnded(source: source, result: "saved")
        let isFirst = !(defaults?.bool(forKey: FlutterPreferenceKeys.firstTodoCreated) ?? false)
        log("todo_created", [
            "source": source,
            "screen_name": "todo_editor",
            "todo_count": taskCount,
            "task_count": taskCount,
            "remaining_count": remainingCount,
            "completed_count": taskCount - remainingCount,
            "has_memo": hasMemo,
            "template_id": templateId,
            "is_first_todo": isFirst,
            "created_count": createdCount,
            "result": "success",
        ])
        guard isFirst else { return }
        defaults?.set(true, forKey: FlutterPreferenceKeys.firstTodoCreated)
        recordFirstContent(type: "todo", todoCount: taskCount)
        log("first_todo_created", [
            "source": source,
            "screen_name": "todo_editor",
            "todo_count": taskCount,
            "is_first_todo": true,
            "setup_type": source == "onboarding" ? "onboarding" : "app",
            "result": "success",
        ])
        tryCompleteActivation()
    }

    func todoCompleted(
        taskCount: Int,
        remainingCount: Int,
        templateId: String,
        source: String = "app",
        eventId: String? = nil,
        occurredAt: Date? = nil
    ) {
        var parameters: [String: Any] = [
            "source": source,
            "screen_name": source == "app" ? "todo_list" : "lockscreen",
            "todo_count": taskCount,
            "task_count": taskCount,
            "remaining_count": remainingCount,
            "completed_count": taskCount - remainingCount,
            "template_id": templateId,
            "setup_type": ["app", "calendar"].contains(source) ? "app" : "live_activity",
            "result": "success",
        ]
        if let eventId { parameters["event_id"] = eventId }
        if let occurredAt { parameters["occurred_at_ms"] = Int64(occurredAt.timeIntervalSince1970 * 1_000) }
        log("todo_completed", parameters)
        recordFirstCompletion(at: occurredAt ?? Date(), source: source)
    }

    func liveActivityStartAttempt(requestId: String, source: String, templateId: String, reason: String) {
        log("live_activity_start_attempt", [
            "request_id": requestId,
            "source": source,
            "template_id": templateId,
            "reason": reason,
            "result": "attempt",
        ])
    }

    func liveActivityStarted(
        taskCount: Int,
        remainingCount: Int,
        hasMemo: Bool,
        templateId: String,
        source: String = "app",
        requestId: String? = nil
    ) {
        let parameters: [String: Any] = [
            "source": source,
            "screen_name": "lockscreen",
            "setup_type": "live_activity",
            "live_activity_enabled": true,
            "todo_count": taskCount,
            "task_count": taskCount,
            "remaining_count": remainingCount,
            "has_memo": hasMemo,
            "template_id": templateId,
            "result": "success",
            "request_id": requestId ?? "unavailable",
            "has_user_content": taskCount > 0 || hasMemo,
        ]
        log("live_activity_start_success", parameters)
        defaults?.set(true, forKey: FlutterPreferenceKeys.liveActivityStarted)
        if taskCount > 0 || hasMemo {
            defaults?.set(true, forKey: FlutterPreferenceKeys.activationHasLiveActivity)
            defaults?.set("live_activity_success", forKey: FlutterPreferenceKeys.activationMethod)
            tryCompleteActivation()
        }
    }

    func liveActivityStartFailed(
        reason: String,
        templateId: String,
        source: String = "app",
        requestId: String? = nil
    ) {
        log("live_activity_start_failed", [
            "source": source,
            "screen_name": "lockscreen",
            "setup_type": "live_activity",
            "reason": reason,
            "error_type": reason,
            "live_activity_enabled": false,
            "template_id": templateId,
            "result": "fail",
            "request_id": requestId ?? "unavailable",
        ])
    }

    func liveActivityEnded() {
        log("lockscreen_activity_ended", ["source": "app", "result": "success"])
    }

    func templateChanged(_ templateId: String) {
        log("lock_screen_template_changed", ["source": "app", "result": "success", "template": templateId])
    }

    func ddaySet() { log("dday_set", ["source": "app", "result": "success"]) }

    func openedApp(from source: String) {
        log(source == "widget" ? "widget_opened" : "lockscreen_open_app", [
            "source": source, "result": "success",
        ])
    }

    // MARK: - SwiftUI v2 navigation and capture

    func topDestinationSelected(destination: String) {
        log("top_destination_selected", [
            "source": "top_control", "destination": destination, "result": "success",
        ])
    }

    func settingsOpened(source: String) {
        log("settings_opened", ["source": source, "result": "success"])
    }

    func displayModeSelected(_ mode: String) {
        log("display_mode_selected", ["source": "display", "mode": mode, "result": "success"])
    }

    func quickCaptureFocused(type: String, source: String = "inline") {
        captureStarted(type: type, source: source)
        log("quick_capture_focused", ["source": source, "type": type, "result": "success"])
    }

    func multilineTodoImported(count: Int, source: String = "inline") {
        log("multiline_todo_imported", ["source": source, "count": count, "result": "success"])
    }

    func memoCreated(source: String, templateId: String? = nil) {
        captureEnded(source: source, result: "saved")
        let isFirst = !(defaults?.bool(forKey: FlutterPreferenceKeys.firstMemoCreated) ?? false)
        var parameters: [String: Any] = [
            "source": source, "result": "success", "is_first_memo": isFirst,
        ]
        if let templateId { parameters["template_id"] = templateId }
        log("memo_created", parameters)
        if isFirst {
            defaults?.set(true, forKey: FlutterPreferenceKeys.firstMemoCreated)
            recordFirstContent(type: "memo", todoCount: 0)
        }
        tryCompleteActivation()
    }

    func liveActivityRestarted() {
        log("live_activity_restarted", ["source": "app", "result": "success"])
    }

    func liveActivityBecameStale() {
        log("live_activity_became_stale", ["source": "app", "result": "success"])
    }

    func widgetSetupStarted() {
        log("widget_setup_guide_viewed", ["source": "display", "result": "success"])
    }

    /// Observed configurations, never a count of Lock Screen impressions.
    func widgetConfigurationsChecked(home: Int, rectangular: Int, inline: Int) {
        let total = home + rectangular + inline
        let state = rectangular + inline > 0 ? "lock_screen" : (home > 0 ? "home_only" : "none")
        let signature = "\(home):\(rectangular):\(inline)"
        let previous = defaults?.string(forKey: "analytics.widget.configuration.signature")
        defaults?.set(state, forKey: "analytics.widget.configuration.state")
        defaults?.set(signature, forKey: "analytics.widget.configuration.signature")
        let parameters: [String: Any] = [
            "home_count": home, "rectangular_count": rectangular, "inline_count": inline,
            "widget_count": total, "configuration_changed": previous != signature,
            "source": "os_configuration", "result": "success",
        ]
        log("widget_configuration_checked", parameters)
        if total > 0 && previous != signature {
            log("widget_configured_detected", parameters)
        }
    }

    func widgetConfigurationCheckFailed(code: Int) {
        log("widget_configuration_check_failed", ["error_code": code, "result": "fail"])
    }

    func widgetInstalledConfirmed(method: String = "os_configuration") {
        log("widget_installed_confirmed", [
            "source": "display", "confirmation_method": method, "result": "success",
        ])
        if method == "os_configuration" {
            defaults?.set(true, forKey: FlutterPreferenceKeys.lockscreenConfirmed)
            defaults?.set("widget_confirmed", forKey: FlutterPreferenceKeys.activationMethod)
            tryCompleteActivation()
        }
    }

    // MARK: - Paywall funnel

    func adEvent(_ name: String, errorCode: Int? = nil, consentState: Int? = nil, placement: String = AdPolicy.placement) {
        var parameters: [String: Any] = [
            "placement": placement,
            "ad_format": "app_open",
            "ad_unit": AdPolicy.appOpenUnitID,
            "ad_is_test": AdPolicy.isTest ? 1 : 0,
        ]
        if let errorCode { parameters["error_code"] = errorCode }
        if let consentState { parameters["consent_state"] = consentState }
        log(name, parameters)
    }

    func adRevenue(value: Decimal, currency: String, precision: Int, placement: String = AdPolicy.placement) {
        // Test callbacks must never be counted as production purchase/ad revenue.
        log(AdPolicy.isTest ? "ad_test_revenue" : "ad_paid_revenue", [
            "placement": placement,
            "ad_format": "app_open",
            "ad_unit": AdPolicy.appOpenUnitID,
            "ad_is_test": AdPolicy.isTest ? 1 : 0,
            "value": NSDecimalNumber(decimal: value).doubleValue,
            "currency": currency,
            "precision": precision,
        ])
    }

    func purchaseApplication(trigger: String, result: String) {
        log("l122_purchase_application", ["paywall_trigger": trigger, "result": result])
    }

    func proDisplayResult(template: String, result: String) {
        log("pro_display_result", ["template_id": template, "result": result])
    }

    func layoutProfileAction(_ action: String, count: Int) {
        // Profile names and user content are intentionally omitted.
        log("layout_profile_\(action)", ["source": "settings", "profile_count": count])
    }

    func paywallSeen(source: String) {
        log("paywall_seen", [
            "source": "app", "screen_name": "paywall", "paywall_trigger": source, "result": "success",
        ])
    }

    /// New in the SwiftUI build: the step between tapping a Pro template and
    /// the paywall, so the drop-off between them becomes measurable.
    func proTemplateTapped(_ templateId: String) {
        log("pro_template_tapped", ["source": "app", "template_id": templateId, "result": "success"])
    }

    func proInfoSheetViewed(_ templateId: String) {
        log("pro_info_sheet_viewed", ["source": "app", "template_id": templateId, "result": "success"])
    }

    func proPreviewViewed(_ templateId: String) {
        log("pro_preview_viewed", ["source": "app", "template_id": templateId, "result": "success"])
    }

    func proPreviewInteracted(_ templateId: String) {
        log("pro_preview_interacted", ["source": "app", "template_id": templateId, "result": "success"])
    }

    func planSelected(
        productId: String,
        source: String,
        price: Decimal?,
        currency: String?,
        isTrial: Bool,
        isDefault: Bool,
        previewTemplate: String?
    ) {
        var parameters = purchaseParameters(
            productId: productId,
            source: source,
            price: price,
            currency: currency,
            isTrial: isTrial,
            previewTemplate: previewTemplate
        )
        parameters["is_default"] = isDefault
        log("plan_selected", parameters)
    }

    func paywallDismissed(source: String, previewTemplate: String?) {
        var parameters: [String: Any] = ["source": "paywall", "paywall_trigger": source, "result": "success"]
        parameters["preview_template"] = previewTemplate ?? "none"
        log("paywall_dismissed", parameters)
    }

    func trialCTATapped(productId: String, source: String, previewTemplate: String?) {
        var parameters: [String: Any] = [
            "source": "paywall", "paywall_trigger": source, "product_id": productId, "result": "success",
        ]
        parameters["preview_template"] = previewTemplate ?? "none"
        log("trial_cta_tapped", parameters)
    }

    func purchaseStarted(
        productId: String,
        source: String,
        price: Decimal?,
        currency: String?,
        isTrial: Bool = false,
        previewTemplate: String? = nil,
        attemptId: String? = nil
    ) {
        verifiedPurchaseEnvironment = "unknown"
        verifiedTrialState = .unknown
        var parameters = purchaseParameters(
            productId: productId,
            source: source,
            price: price,
            currency: currency,
            isTrial: isTrial,
            previewTemplate: previewTemplate,
            attemptId: attemptId
        )
        parameters["screen_name"] = "paywall"
        log("purchase_started", parameters)
    }

    func purchaseCompleted(
        productId: String,
        source: String,
        price: Decimal?,
        currency: String?,
        isTrial: Bool = false,
        previewTemplate: String? = nil,
        attemptId: String? = nil
    ) {
        var parameters = purchaseParameters(
            productId: productId,
            source: source,
            price: price,
            currency: currency,
            isTrial: isTrial,
            previewTemplate: previewTemplate,
            attemptId: attemptId
        )
        parameters["transaction_environment"] = verifiedPurchaseEnvironment
        parameters["transaction_trial_state"] = verifiedTrialState.rawValue
        parameters["trial_basis"] = verifiedTrialState == .unknown ? "unknown" : "verified_transaction"
        parameters["is_trial"] = verifiedTrialState == .unknown ? nil : (verifiedTrialState == .freeTrial)
        log("purchase_completed", parameters)
    }

    func purchasePending(productId: String, source: String, attemptId: String, previewTemplate: String?) {
        var parameters: [String: Any] = [
            "source": "paywall", "paywall_trigger": source, "product_id": productId,
            "attempt_id": attemptId, "result": "pending",
        ]
        parameters["preview_template"] = previewTemplate ?? "none"
        log("purchase_pending", parameters)
    }

    func purchaseValueApplied(
        productId: String,
        source: String,
        price: Decimal?,
        currency: String?,
        isTrial: Bool,
        previewTemplate: String?,
        attemptId: String? = nil
    ) {
        let parameters = purchaseParameters(
            productId: productId,
            source: source,
            price: price,
            currency: currency,
            isTrial: isTrial,
            previewTemplate: previewTemplate,
            attemptId: attemptId
        )
        log("purchase_value_applied", parameters)
    }

    private func purchaseParameters(
        productId: String,
        source: String,
        price: Decimal?,
        currency: String?,
        isTrial: Bool,
        previewTemplate: String?,
        attemptId: String? = nil
    ) -> [String: Any] {
        var parameters: [String: Any] = [
            "source": "paywall",
            "paywall_trigger": source,
            "product_id": productId,
            "plan": analyticsPlan(productId),
            "is_trial": isTrial,
            "trial_basis": "quoted_context",
            "result": "success",
        ]
        if let price {
            let value = NSDecimalNumber(decimal: price).doubleValue
            parameters["value"] = isTrial ? 0 : value
            parameters["price"] = value
            parameters["quoted_price"] = value
            parameters["value_basis"] = isTrial ? "free_trial" : "quoted_product_price"
        }
        parameters["is_revenue_event"] = 0
        if let currency { parameters["currency"] = currency }
        parameters["preview_template"] = previewTemplate ?? "none"
        if let attemptId { parameters["attempt_id"] = attemptId }
        return parameters
    }

    private func analyticsPlan(_ productId: String) -> String {
        if ProductIdentifiers.isYearly(productId) { return "yearly" }
        if productId == ProductIdentifiers.monthly { return "monthly" }
        if productId == ProductIdentifiers.lifetime { return "lifetime" }
        return "unknown"
    }

    func purchaseCancelled(
        productId: String,
        source: String,
        price: Decimal? = nil,
        currency: String? = nil,
        isTrial: Bool = false,
        previewTemplate: String? = nil,
        attemptId: String? = nil
    ) {
        var parameters = purchaseParameters(
            productId: productId, source: source, price: price, currency: currency,
            isTrial: isTrial, previewTemplate: previewTemplate, attemptId: attemptId
        )
        parameters["result"] = "cancelled"
        log("purchase_cancelled", parameters)
    }

    func purchaseFailed(
        productId: String,
        source: String,
        price: Decimal? = nil,
        currency: String? = nil,
        isTrial: Bool = false,
        previewTemplate: String? = nil,
        attemptId: String? = nil
    ) {
        var parameters = purchaseParameters(
            productId: productId, source: source, price: price, currency: currency,
            isTrial: isTrial, previewTemplate: previewTemplate, attemptId: attemptId
        )
        parameters["result"] = "fail"
        log("purchase_failed", parameters)
    }

    enum VerifiedTrialState: String { case unknown, freeTrial = "free_trial", notTrial = "not_trial" }
    private var verifiedPurchaseEnvironment = "unknown"
    private var verifiedTrialState: VerifiedTrialState = .unknown
    func purchaseVerifiedEnvironment(_ environment: String, trialState: VerifiedTrialState = .unknown) {
        verifiedPurchaseEnvironment = ["Production", "Sandbox", "Xcode"].contains(environment) ? environment.lowercased() : "unknown"
        verifiedTrialState = trialState
    }

    func restoreCompleted(result: String) {
        log("restore_completed", ["source": "app", "result": result])
    }

    func reminderAction(_ action: String, kind: String, source: String = "settings") {
        log("reminder_action", ["source": source, "action": action, "kind": kind, "result": "success"])
    }

    func cardSaveFailed(operation: String, source: String, errorCode: String = "write_failed") {
        if ["create_todo", "create_memo"].contains(operation) {
            captureEnded(source: source, result: "failed")
        }
        log("card_save_failed", [
            "source": source, "operation": operation, "error_code": errorCode, "result": "fail",
        ])
    }

    func lockscreenInteracted(action: String, surface: String, eventId: String, occurredAt: Date) {
        log("lockscreen_interacted", [
            "source": surface, "surface": surface, "action": action, "event_id": eventId,
            "occurred_at_ms": Int64(occurredAt.timeIntervalSince1970 * 1_000), "result": "success",
        ])
    }

    func appReturned(entrySource: String, activityState: String, hasTodayContent: Bool, now: Date = Date()) {
        guard let defaults else { return }
        defer { defaults.set(now.timeIntervalSince1970, forKey: FlutterPreferenceKeys.lastForegroundAt) }
        let previousSeconds = defaults.double(forKey: FlutterPreferenceKeys.lastForegroundAt)
        guard previousSeconds > 0, daysSinceInstall > 0 else { return }
        let day = FlutterDate.dateKey(now)
        guard defaults.string(forKey: FlutterPreferenceKeys.lastReturnedDay) != day else { return }
        defaults.set(day, forKey: FlutterPreferenceKeys.lastReturnedDay)
        let previous = Date(timeIntervalSince1970: previousSeconds)
        let elapsedDays = max(0, Calendar.current.dateComponents([.day], from: previous, to: now).day ?? 0)
        log("app_returned", [
            "source": "app", "entry_source": entrySource, "cohort_age_days": daysSinceInstall,
            "days_since_previous_foreground": elapsedDays, "activity_state": activityState,
            "has_today_content": hasTodayContent, "result": "success",
        ])
    }

    func temporaryTrialStarted(source: String) {
        log("temporary_pro_trial_started", ["source": source, "duration_hours": 24, "result": "success"])
    }

    func reviewEligibilityReached(_ parameters: [String: Any]) {
        log("review_eligibility_reached", parameters)
    }

    func reviewPromptRequested(_ parameters: [String: Any]) {
        log("review_prompt_requested", parameters)
    }

    func reviewPromptDeferred(reason: String, parameters: [String: Any]) {
        log("review_prompt_deferred", parameters.merging(["reason": reason]) { _, new in new })
    }

    func reviewStoreLinkOpened() {
        log("review_store_link_opened", ["source": "settings", "result": "success"])
    }

    func reviewRequestSkipped(reason: String, parameters: [String: Any]) {
        log("review_request_skipped", parameters.merging(["reason": reason]) { _, new in new })
    }

    // MARK: - Migration

    func record(migration outcome: FlutterDataMigrator.Outcome?) {
        guard let outcome else { return }
        switch outcome {
        case .migrated(let count):
            log("migration_completed", ["source": "app", "card_count": count, "result": "success"])
        case .failed:
            log("migration_failed", ["source": "app", "reason": "migration_failed", "result": "fail"])
        case .alreadyMigrated, .nothingToMigrate:
            break
        }
    }

    private func recordFirstCompletion(at date: Date, source: String) {
        guard let defaults, defaults.object(forKey: "analytics.first_completion_at") == nil else { return }
        defaults.set(date.timeIntervalSince1970, forKey: "analytics.first_completion_at")
        let install = defaults.string(forKey: FlutterPreferenceKeys.installDate).flatMap { FlutterDate.parse($0) }
        let elapsed = install.map { max(0, Int(date.timeIntervalSince($0))) } ?? -1
        log("l122_first_completion", ["source": source, "occurred_at_ms": Int64(date.timeIntervalSince1970 * 1000),
            "elapsed_seconds": elapsed, "cohort": defaults.string(forKey: "analytics.release_cohort") ?? "unknown", "result": "success"])
    }

    // MARK: - Extension queue

    /// Extensions cannot reach Firebase, so they append to an App Group queue
    /// that the app drains here. Events carry the delay they accumulated,
    /// because Firebase stamps receipt time rather than occurrence time.
    func flushQueuedEvents() {
        let events = store.queuedAnalyticsEvents()
        guard !events.isEmpty, backend.isEnabled else { return }
        let dropped = defaults?.integer(forKey: "analytics.queue_dropped_total") ?? 0
        let reported = defaults?.integer(forKey: "analytics.queue_dropped_reported") ?? 0
        if dropped > reported {
            log("l122_queue_health", ["source": "queue_merge", "dropped_delta": dropped - reported, "result": "overflow"])
            defaults?.set(dropped, forKey: "analytics.queue_dropped_reported")
        }
        for event in events {
            var parameters = event.parameters
            parameters["queued_delay_hours"] = event.queuedDelayHours()
            parameters["occurred_at_ms"] = Int64(event.createdAt.timeIntervalSince1970 * 1_000)
            parameters["event_id"] = event.id
            parameters["forwarded_at_ms"] = Int64(Date().timeIntervalSince1970 * 1000)
            if parameters["origin_app_version"] == nil { parameters["origin_app_version"] = "unknown_legacy" }
            log(event.name, parameters)
            if event.name == "l122_external_commit", parameters["action"] as? String == "complete", parameters["result"] as? String == "success" {
                let actionDate = (parameters["action_occurred_at_ms"] as? NSNumber).map {
                    Date(timeIntervalSince1970: $0.doubleValue / 1000)
                } ?? event.createdAt
                recordFirstCompletion(at: actionDate, source: parameters["action_origin"] as? String ?? "unknown")
            }
            store.acknowledgeQueuedAnalyticsEvents(ids: Set([event.id]))
        }
    }

    // MARK: - Activation state

    private func recordFirstContent(type: String, todoCount: Int) {
        if defaults?.string(forKey: FlutterPreferenceKeys.firstContentCreatedAt) == nil {
            let now = FlutterDate.utcString(from: Date())
            defaults?.set(now, forKey: FlutterPreferenceKeys.firstContentCreatedAt)
            if type == "todo" {
                defaults?.set(now, forKey: FlutterPreferenceKeys.firstTodoCreatedAt)
            }
            defaults?.set(type, forKey: FlutterPreferenceKeys.activationContentType)
            defaults?.set(todoCount, forKey: FlutterPreferenceKeys.activationTodoCount)
        }
    }

    /// Activation means: saved a todo or memo and got that content onto a verified surface.
    /// Logged at most once per install.
    func tryCompleteActivation() {
        guard
            let defaults,
            defaults.bool(forKey: FlutterPreferenceKeys.firstTodoCreated)
                || defaults.bool(forKey: FlutterPreferenceKeys.firstMemoCreated),
            let method = defaults.string(forKey: FlutterPreferenceKeys.activationMethod),
            !method.isEmpty
        else { return }

        let widgetConfirmed = defaults.bool(forKey: FlutterPreferenceKeys.lockscreenConfirmed)
        let hasLiveActivity = defaults.bool(forKey: FlutterPreferenceKeys.activationHasLiveActivity)
        guard widgetConfirmed || hasLiveActivity else { return }

        defaults.set(true, forKey: FlutterPreferenceKeys.activationCompleted)
        guard !defaults.bool(forKey: FlutterPreferenceKeys.activationEventLogged) else { return }

        log("activation_complete", [
            "source": "app",
            "screen_name": "activation",
            "activation_method": method,
            "activation_definition": "content_and_setup_v2",
            "content_type": defaults.string(forKey: FlutterPreferenceKeys.activationContentType) ?? "unknown",
            "setup_type": widgetConfirmed && hasLiveActivity
                ? "live_activity_and_widget"
                : (widgetConfirmed ? "widget" : "live_activity"),
            "todo_count": defaults.integer(forKey: FlutterPreferenceKeys.activationTodoCount),
            "has_live_activity": hasLiveActivity,
            "widget_setup_confirmed": widgetConfirmed,
            "days_since_first_open": daysSinceInstall,
            "time_to_value_seconds": timeToValueSeconds,
            "result": "success",
        ])
        defaults.set(true, forKey: FlutterPreferenceKeys.activationEventLogged)
        let installed = defaults.string(forKey: FlutterPreferenceKeys.installDate).flatMap { FlutterDate.parse($0) }
        log("l122_first_value", ["source": "app", "milestone": "content_and_setup",
            "elapsed_seconds": installed.map { max(0, Int(Date().timeIntervalSince($0))) } ?? -1,
            "cohort": defaults.string(forKey: "analytics.release_cohort") ?? "unknown", "result": "success"])
    }

    var hasCompletedActivation: Bool {
        defaults?.bool(forKey: FlutterPreferenceKeys.activationCompleted) ?? false
    }

    private var timeToValueSeconds: Int {
        guard let stored = defaults?.string(forKey: FlutterPreferenceKeys.firstContentCreatedAt),
              let createdAt = FlutterDate.parse(stored),
              let installedRaw = defaults?.string(forKey: FlutterPreferenceKeys.installDate),
              let installedAt = FlutterDate.parse(installedRaw)
        else { return -1 }
        return max(0, Int(createdAt.timeIntervalSince(installedAt)))
    }
}

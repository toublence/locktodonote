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
            "app_build": AppInfo.build,
            "implementation": "swiftui",
            "days_since_install": daysSinceInstall,
            "app_version": AppInfo.versionDisplay,
            "is_premium": isPremium ? 1 : 0,
            "trial_type": trialType,
            "ios_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "device_family": "ios",
        ]
        parameters["language"] = locale.language.languageCode?.identifier ?? "unknown"
        if let region = locale.region?.identifier {
            parameters["country"] = region
        }
        return parameters
    }

    var isPremium = false
    var trialType = "none"

    private func log(_ name: String, _ parameters: [String: Any] = [:]) {
        var merged = commonParameters
        for (key, value) in parameters {
            // Firebase rejects booleans; the Flutter build coerced them to 0/1.
            merged[key] = (value as? Bool).map { $0 ? 1 : 0 } ?? value
        }
        backend.log(name: name, parameters: merged)
        reviewCoordinator?.record(event: name, parameters: merged)
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
        guard defaults?.string(forKey: FlutterPreferenceKeys.installDate) == nil else { return }
        defaults?.set(FlutterDate.utcString(from: Date()), forKey: FlutterPreferenceKeys.installDate)
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
            "setup_type": source == "app" ? "app" : "live_activity",
            "result": "success",
        ]
        if let eventId { parameters["event_id"] = eventId }
        if let occurredAt { parameters["occurred_at_ms"] = Int64(occurredAt.timeIntervalSince1970 * 1_000) }
        log("todo_completed", parameters)
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
        log(source == "widget" ? "widget_open_app" : "lockscreen_open_app", [
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
        log("quick_capture_focused", ["source": source, "type": type, "result": "success"])
    }

    func multilineTodoImported(count: Int, source: String = "inline") {
        log("multiline_todo_imported", ["source": source, "count": count, "result": "success"])
    }

    func memoCreated(source: String, templateId: String? = nil) {
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
        log("widget_setup_started", ["source": "display", "result": "success"])
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
        let parameters = purchaseParameters(
            productId: productId,
            source: source,
            price: price,
            currency: currency,
            isTrial: isTrial,
            previewTemplate: previewTemplate,
            attemptId: attemptId
        )
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
            "result": "success",
        ]
        if let price {
            let value = NSDecimalNumber(decimal: price).doubleValue
            parameters["value"] = value
            parameters["price"] = value
        }
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

    func restoreCompleted(result: String) {
        log("restore_completed", ["source": "app", "result": result])
    }

    func reminderAction(_ action: String, kind: String, source: String = "settings") {
        log("reminder_action", ["source": source, "action": action, "kind": kind, "result": "success"])
    }

    func cardSaveFailed(operation: String, source: String, errorCode: String = "write_failed") {
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
        case .failed(let reason):
            log("migration_failed", ["source": "app", "reason": reason, "result": "fail"])
        case .alreadyMigrated, .nothingToMigrate:
            break
        }
    }

    // MARK: - Extension queue

    /// Extensions cannot reach Firebase, so they append to an App Group queue
    /// that the app drains here. Events carry the delay they accumulated,
    /// because Firebase stamps receipt time rather than occurrence time.
    func flushQueuedEvents() {
        let events = store.queuedAnalyticsEvents()
        guard !events.isEmpty, backend.isEnabled else { return }
        for event in events {
            var parameters = event.parameters
            parameters["queued_delay_hours"] = event.queuedDelayHours()
            parameters["occurred_at_ms"] = Int64(event.createdAt.timeIntervalSince1970 * 1_000)
            parameters["event_id"] = event.id
            log(event.name, parameters)
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

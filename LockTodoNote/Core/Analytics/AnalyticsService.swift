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
            "days_since_install": daysSinceInstall,
            "app_version": AppInfo.versionDisplay,
            "is_premium": isPremium ? 1 : 0,
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

    private func log(_ name: String, _ parameters: [String: Any] = [:]) {
        var merged = commonParameters
        for (key, value) in parameters {
            // Firebase rejects booleans; the Flutter build coerced them to 0/1.
            merged[key] = (value as? Bool).map { $0 ? 1 : 0 } ?? value
        }
        backend.log(name: name, parameters: merged)
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

    func lockscreenPreviewSeen(templateId: String, todoCount: Int) {
        defaults?.set(true, forKey: FlutterPreferenceKeys.lockscreenPreviewSeen)
        log("lockscreen_preview_seen", [
            "source": "onboarding",
            "screen_name": "activation_preview",
            "template_id": templateId,
            "todo_count": todoCount,
            "preview_type": "lockscreen_mock",
            "result": "success",
        ])
    }

    func lockscreenSetupConfirmed(visible: Bool, todoCount: Int) {
        log(visible ? "lockscreen_setup_confirm_yes" : "lockscreen_setup_confirm_no", [
            "source": "app",
            "screen_name": "lockscreen_setup_confirmation",
            "setup_type": "lockscreen_confirmation",
            "result": "success",
        ])
        guard visible else { return }
        defaults?.set(true, forKey: FlutterPreferenceKeys.lockscreenConfirmed)
        recordActivationSignal(todoCount: todoCount, method: "user_confirmed_widget")
    }

    // MARK: - Activation

    func todoCreated(taskCount: Int, remainingCount: Int, hasMemo: Bool, templateId: String, source: String = "app") {
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
            "result": "success",
        ])
        guard isFirst else { return }
        log("first_todo_created", [
            "source": source,
            "screen_name": "todo_editor",
            "todo_count": taskCount,
            "is_first_todo": true,
            "setup_type": source == "onboarding" ? "onboarding" : "app",
            "result": "success",
        ])
        recordActivationSignal(todoCount: taskCount, method: nil)
    }

    func todoCompleted(taskCount: Int, remainingCount: Int, templateId: String, source: String = "app") {
        log("todo_completed", [
            "source": source,
            "screen_name": source == "app" ? "todo_list" : "lockscreen",
            "todo_count": taskCount,
            "task_count": taskCount,
            "remaining_count": remainingCount,
            "completed_count": taskCount - remainingCount,
            "template_id": templateId,
            "setup_type": source == "app" ? "app" : "live_activity",
            "result": "success",
        ])
    }

    /// A completion that happened on the Lock Screen while the app was closed.
    func todoCompletedFromExtension(source: String) {
        log("todo_completed", [
            "source": source,
            "screen_name": "lockscreen",
            "setup_type": "live_activity",
            "result": "success",
        ])
    }

    func shortcutQuickAddsMerged(count: Int) {
        log("shortcut_quick_add", ["source": "shortcut", "result": "success", "merged_count": count])
    }

    func liveActivityStarted(taskCount: Int, remainingCount: Int, hasMemo: Bool, templateId: String, source: String = "app") {
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
        ]
        log("live_activity_start_success", parameters)
        log("live_activity_started", parameters)
        defaults?.set(true, forKey: FlutterPreferenceKeys.liveActivityStarted)
        defaults?.set(true, forKey: FlutterPreferenceKeys.activationHasLiveActivity)
        recordActivationSignal(todoCount: taskCount, method: "live_activity_success")
    }

    func liveActivityStartFailed(reason: String, templateId: String) {
        log("live_activity_start_failed", [
            "source": "app",
            "screen_name": "lockscreen",
            "setup_type": "live_activity",
            "reason": reason,
            "error_type": reason,
            "live_activity_enabled": false,
            "template_id": templateId,
            "result": "fail",
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

    func quickCaptureFocused(type: String) {
        log("quick_capture_focused", ["source": "inline", "type": type, "result": "success"])
    }

    func multilineTodoImported(count: Int) {
        log("multiline_todo_imported", ["source": "inline", "count": count, "result": "success"])
    }

    func memoCreated(source: String) {
        log("memo_created", ["source": source, "result": "success"])
    }

    func liveActivityRestarted() {
        log("live_activity_restarted", ["source": "app", "result": "success"])
    }

    func widgetSetupStarted() {
        log("widget_setup_started", ["source": "display", "result": "success"])
    }

    func widgetInstalledConfirmed() {
        log("widget_installed_confirmed", ["source": "display", "result": "success"])
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

    func purchaseStarted(productId: String, source: String, price: Decimal?, currency: String?) {
        var parameters: [String: Any] = [
            "source": "paywall",
            "screen_name": "paywall",
            "paywall_trigger": source,
            "product_id": productId,
            "result": "success",
        ]
        if let price { parameters["value"] = NSDecimalNumber(decimal: price).doubleValue }
        if let currency { parameters["currency"] = currency }
        log("purchase_started", parameters)
    }

    func purchaseCompleted(productId: String, source: String, price: Decimal?, currency: String?) {
        var parameters: [String: Any] = [
            "source": "paywall",
            "paywall_trigger": source,
            "product_id": productId,
            "result": "success",
        ]
        if let price { parameters["value"] = NSDecimalNumber(decimal: price).doubleValue }
        if let currency { parameters["currency"] = currency }
        log("purchase_completed", parameters)
    }

    func purchaseCancelled(productId: String, source: String) {
        log("purchase_cancelled", [
            "source": "paywall", "paywall_trigger": source, "product_id": productId, "result": "success",
        ])
    }

    func purchaseFailed(productId: String, source: String) {
        log("purchase_failed", [
            "source": "paywall", "paywall_trigger": source, "product_id": productId, "result": "fail",
        ])
    }

    func restoreCompleted(restored: Bool) {
        log("restore_completed", ["source": "app", "result": "success", "restored": restored])
    }

    func temporaryTrialStarted(source: String) {
        log("temporary_pro_trial_started", ["source": source, "duration_hours": 24, "result": "success"])
    }

    func reviewRequested() { log("review_requested", ["source": "app", "result": "success"]) }

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
            log(event.name, parameters)
        }
        store.clearQueuedAnalyticsEvents()
    }

    // MARK: - Activation state

    private func recordActivationSignal(todoCount: Int, method: String?) {
        defaults?.set(true, forKey: FlutterPreferenceKeys.firstTodoCreated)
        if defaults?.string(forKey: FlutterPreferenceKeys.firstTodoCreatedAt) == nil {
            defaults?.set(
                FlutterDate.utcString(from: Date()),
                forKey: FlutterPreferenceKeys.firstTodoCreatedAt
            )
        }
        if let method {
            defaults?.set(method, forKey: FlutterPreferenceKeys.activationMethod)
        }
        defaults?.set(todoCount, forKey: FlutterPreferenceKeys.activationTodoCount)
        tryCompleteActivation()
    }

    /// Activation means: created a todo *and* got the card onto the Lock Screen.
    /// Logged at most once per install.
    func tryCompleteActivation() {
        guard
            let defaults,
            defaults.bool(forKey: FlutterPreferenceKeys.firstTodoCreated),
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
            "setup_type": widgetConfirmed && hasLiveActivity
                ? "live_activity_and_widget"
                : (widgetConfirmed ? "widget" : "live_activity"),
            "todo_count": defaults.integer(forKey: FlutterPreferenceKeys.activationTodoCount),
            "has_live_activity": hasLiveActivity,
            "widget_setup_confirmed": widgetConfirmed,
            "days_since_first_open": daysSinceInstall,
            "result": "success",
        ])
        defaults.set(true, forKey: FlutterPreferenceKeys.activationEventLogged)
    }

    var hasCompletedActivation: Bool {
        defaults?.bool(forKey: FlutterPreferenceKeys.activationCompleted) ?? false
    }
}

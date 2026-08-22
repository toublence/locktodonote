import Foundation
import Combine
import LockTodoNoteShared

/// Applies the app's review-request policy without creating a custom rating UI.
@MainActor
final class ReviewRequestCoordinator: ObservableObject {
    private enum Key {
        static let eligible = "locktodonote.review.eligible.v2"
        static let eligibleLogged = "locktodonote.review.eligible_logged.v2"
        static let lastRequestDate = "locktodonote.review.last_request_date.v2"
        static let lastRequestVersion = "locktodonote.review.last_request_version.v2"
        static let usageDates = "locktodonote.review.usage_dates.v2"
        static let todoCreated = "locktodonote.review.todo_created.v2"
        static let memoCreated = "locktodonote.review.memo_created.v2"
        static let todoCompleted = "locktodonote.review.todo_completed.v2"
        static let liveActivitySuccess = "locktodonote.review.live_activity_success.v2"
        static let lockScreenInteractions = "locktodonote.review.lockscreen_interactions.v2"
        static let coreSuccess = "locktodonote.review.core_success.v2"
        static let lastTrigger = "locktodonote.review.last_trigger.v2"
    }

    private let defaults: UserDefaults?
    private weak var analytics: AnalyticsService?

    init(store: AppGroupStore = AppGroupStore()) {
        defaults = store.defaults
    }

    func attachAnalytics(_ analytics: AnalyticsService) {
        self.analytics = analytics
    }

    func recordUsageDay(_ date: Date = Date()) {
        guard let defaults else { return }
        var dates = Set(defaults.stringArray(forKey: Key.usageDates) ?? [])
        dates.insert(FlutterDate.dateKey(date))
        defaults.set(Array(dates).sorted(), forKey: Key.usageDates)
        evaluate(trigger: "foreground")
    }

    /// Receives the same successful events sent to Firebase, including events
    /// drained from Widget and Live Activity queues.
    func record(event name: String, parameters: [String: Any]) {
        guard defaults != nil, !name.hasPrefix("review_") else { return }
        if (parameters["review_signal_recorded"] as? NSNumber)?.boolValue == true {
            evaluate(trigger: name)
            return
        }

        switch name {
        case "todo_created":
            increment(Key.todoCreated, by: max(1, parameters["created_count"] as? Int ?? 1))
        case "memo_created":
            increment(Key.memoCreated)
        case "todo_completed":
            increment(Key.todoCompleted)
            increment(Key.coreSuccess)
            if let source = parameters["source"] as? String, source != "app", source != "inline", source != "calendar" {
                increment(Key.lockScreenInteractions)
            }
        case "widget_todo_completed", "dynamic_island_interacted":
            increment(Key.lockScreenInteractions)
            increment(Key.coreSuccess)
        case "live_activity_start_success":
            increment(Key.liveActivitySuccess)
            increment(Key.coreSuccess)
        case "live_activity_restarted", "multiline_todo_imported", "morning_briefing_test_success":
            increment(Key.coreSuccess)
        default:
            break
        }

        evaluate(trigger: name)
    }

    func evaluate(trigger: String) {
        guard let defaults else { return }
        guard isEligible else { return }

        defaults.set(true, forKey: Key.eligible)
        defaults.set(trigger, forKey: Key.lastTrigger)
        guard !defaults.bool(forKey: Key.eligibleLogged) else { return }
        defaults.set(true, forKey: Key.eligibleLogged)
        analytics?.reviewEligibilityReached(parameters(trigger: trigger))
    }

    /// Called after the app returns to the foreground and the UI has settled.
    func claimForegroundRequest(isBlocked: Bool) -> Bool {
        guard let defaults else { return false }
        guard defaults.bool(forKey: Key.eligible) else {
            analytics?.reviewRequestSkipped(reason: "not_eligible", parameters: parameters(trigger: "foreground"))
            return false
        }
        guard !isBlocked else {
            analytics?.reviewPromptDeferred(reason: "ui_blocked", parameters: parameters(trigger: "foreground"))
            return false
        }
        guard canRequestForCurrentVersion else {
            analytics?.reviewRequestSkipped(reason: "version_or_interval", parameters: parameters(trigger: "foreground"))
            return false
        }

        let trigger = defaults.string(forKey: Key.lastTrigger) ?? "foreground"
        defaults.set(false, forKey: Key.eligible)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastRequestDate)
        defaults.set(appVersion, forKey: Key.lastRequestVersion)
        analytics?.reviewPromptRequested(parameters(trigger: trigger))
        return true
    }

    #if DEBUG
    func forceEligibility() {
        defaults?.set(true, forKey: Key.eligible)
        defaults?.set("debug_force", forKey: Key.lastTrigger)
        defaults?.removeObject(forKey: Key.lastRequestVersion)
        defaults?.removeObject(forKey: Key.lastRequestDate)
    }
    #endif

    private var isEligible: Bool {
        guard let defaults else { return false }
        let usageDays = defaults.stringArray(forKey: Key.usageDates)?.count ?? 0
        let created = defaults.integer(forKey: Key.todoCreated) + defaults.integer(forKey: Key.memoCreated)
        let completions = defaults.integer(forKey: Key.todoCompleted)
        let interactions = defaults.integer(forKey: Key.lockScreenInteractions)
        return defaults.bool(forKey: FlutterPreferenceKeys.activationCompleted)
            && usageDays >= 3
            && created >= 5
            && defaults.integer(forKey: Key.liveActivitySuccess) >= 1
            && (completions >= 3 || interactions >= 2)
            && canRequestForCurrentVersion
    }

    private var canRequestForCurrentVersion: Bool {
        guard let defaults else { return false }
        guard defaults.string(forKey: Key.lastRequestVersion) != appVersion else { return false }
        let last = defaults.double(forKey: Key.lastRequestDate)
        return last == 0 || Date().timeIntervalSince1970 - last >= 14 * 24 * 60 * 60
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private func increment(_ key: String, by amount: Int = 1) {
        guard let defaults else { return }
        defaults.set(defaults.integer(forKey: key) + amount, forKey: key)
    }

    private func parameters(trigger: String) -> [String: Any] {
        guard let defaults else { return ["trigger": trigger, "app_version": appVersion] }
        return [
            "trigger": trigger,
            "app_version": appVersion,
            "distinct_usage_days": defaults.stringArray(forKey: Key.usageDates)?.count ?? 0,
            "todo_created_count": defaults.integer(forKey: Key.todoCreated),
            "memo_created_count": defaults.integer(forKey: Key.memoCreated),
            "todo_completed_count": defaults.integer(forKey: Key.todoCompleted),
            "live_activity_success_count": defaults.integer(forKey: Key.liveActivitySuccess),
            "core_success_count": defaults.integer(forKey: Key.coreSuccess),
        ]
    }
}

import Foundation

/// Stores review signals in the App Group, including signals produced while
/// only a Widget, Live Activity or Shortcut extension is running.
public struct ReviewEligibilityRecorder: Sendable {
    public enum Signal: Sendable {
        case todoCreated(Int)
        case memoCreated(Int)
        case todoCompleted(lockScreenInteraction: Bool)
        case liveActivitySuccess
        case coreSuccess
    }

    private enum Key {
        static let eligible = "locktodonote.review.eligible.v2"
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

    private let store: AppGroupStore

    public init(store: AppGroupStore = AppGroupStore()) {
        self.store = store
    }

    public func record(_ signal: Signal, trigger: String, at date: Date = Date()) {
        guard let defaults = store.defaults else { return }
        var dates = Set(defaults.stringArray(forKey: Key.usageDates) ?? [])
        dates.insert(FlutterDate.dateKey(date))
        defaults.set(Array(dates).sorted(), forKey: Key.usageDates)

        switch signal {
        case .todoCreated(let count):
            increment(Key.todoCreated, by: max(1, count), defaults: defaults)
        case .memoCreated(let count):
            increment(Key.memoCreated, by: max(1, count), defaults: defaults)
        case .todoCompleted(let interaction):
            increment(Key.todoCompleted, defaults: defaults)
            increment(Key.coreSuccess, defaults: defaults)
            if interaction { increment(Key.lockScreenInteractions, defaults: defaults) }
        case .liveActivitySuccess:
            increment(Key.liveActivitySuccess, defaults: defaults)
            increment(Key.coreSuccess, defaults: defaults)
        case .coreSuccess:
            increment(Key.coreSuccess, defaults: defaults)
        }

        guard qualifies(defaults: defaults, date: date) else { return }
        defaults.set(true, forKey: Key.eligible)
        defaults.set(trigger, forKey: Key.lastTrigger)
    }

    private func qualifies(defaults: UserDefaults, date: Date) -> Bool {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        guard defaults.string(forKey: Key.lastRequestVersion) != version else { return false }
        let last = defaults.double(forKey: Key.lastRequestDate)
        guard last == 0 || date.timeIntervalSince1970 - last >= 14 * 24 * 60 * 60 else { return false }
        let usageDays = defaults.stringArray(forKey: Key.usageDates)?.count ?? 0
        let created = defaults.integer(forKey: Key.todoCreated) + defaults.integer(forKey: Key.memoCreated)
        return defaults.bool(forKey: FlutterPreferenceKeys.activationCompleted)
            && usageDays >= 3
            && created >= 5
            && defaults.integer(forKey: Key.liveActivitySuccess) >= 1
            && (defaults.integer(forKey: Key.todoCompleted) >= 3
                || defaults.integer(forKey: Key.lockScreenInteractions) >= 2)
    }

    private func increment(_ key: String, by amount: Int = 1, defaults: UserDefaults) {
        defaults.set(defaults.integer(forKey: key) + amount, forKey: key)
    }
}

import Foundation
import UserNotifications
import LockTodoNoteShared

/// Local reminders that bring people back to plan their day.
///
/// Local only — the app has no push entitlement and never had one.
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var settings: ReminderSettings {
        didSet {
            settings.save(to: defaults)
            Task { await reschedule() }
        }
    }

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults?
    private weak var analytics: AnalyticsService?

    private enum Identifier {
        static let morning = "locktodonote.reminder.morning"
        static let evening = "locktodonote.reminder.evening"
    }

    init(store: AppGroupStore = AppGroupStore(), center: UNUserNotificationCenter = .current()) {
        self.center = center
        self.defaults = store.defaults
        self.settings = ReminderSettings.load(from: store.defaults)
        super.init()
        center.delegate = self
    }

    func attachAnalytics(_ analytics: AnalyticsService) {
        self.analytics = analytics
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshAuthorizationStatus()
        if granted { await reschedule() }
        return granted
    }

    /// Rebuilds both reminders from current settings. Cheap enough to call on
    /// every change, which avoids drift between settings and what is scheduled.
    func reschedule() async {
        center.removePendingNotificationRequests(
            withIdentifiers: [Identifier.morning, Identifier.evening]
        )
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        if settings.morningEnabled {
            await schedule(
                identifier: Identifier.morning,
                hour: settings.morningHour,
                minute: settings.morningMinute,
                kind: "morning",
                title: appString(localized: "reminder.morningTitle", defaultValue: "Plan your day"),
                body: appString(localized: "reminder.morningBody",
                    defaultValue: "Set today's card so it's waiting on your Lock Screen."
                )
            )
        }
        if settings.eveningEnabled {
            await schedule(
                identifier: Identifier.evening,
                hour: settings.eveningHour,
                minute: settings.eveningMinute,
                kind: "evening",
                title: appString(localized: "reminder.eveningTitle", defaultValue: "Wrap up today"),
                body: appString(localized: "reminder.eveningBody",
                    defaultValue: "Check off what you finished and set up tomorrow."
                )
            )
        }
    }

    private func schedule(
        identifier: String,
        hour: Int,
        minute: Int,
        kind: String,
        title: String,
        body: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["reminder_kind": kind]

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            // Repeating calendar trigger: fires at this wall-clock time daily,
            // and follows the device across time zones.
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let kind = response.notification.request.content.userInfo["reminder_kind"] as? String ?? "unknown"
        completionHandler()
        Task { @MainActor [weak self] in
            self?.analytics?.reminderAction("opened", kind: kind, source: "notification")
        }
    }
}

/// Reminder preferences, stored under the same keys the Flutter build used.
struct ReminderSettings: Equatable, Sendable {
    var morningEnabled: Bool
    var morningHour: Int
    var morningMinute: Int
    var eveningEnabled: Bool
    var eveningHour: Int
    var eveningMinute: Int

    static let `default` = ReminderSettings(
        morningEnabled: false,
        morningHour: 8,
        morningMinute: 0,
        eveningEnabled: false,
        eveningHour: 21,
        eveningMinute: 0
    )

    static func load(from defaults: UserDefaults?) -> ReminderSettings {
        guard let defaults else { return .default }
        return ReminderSettings(
            morningEnabled: defaults.bool(forKey: FlutterPreferenceKeys.morningReminderEnabled),
            morningHour: defaults.object(forKey: FlutterPreferenceKeys.morningReminderHour) as? Int ?? 8,
            morningMinute: defaults.object(forKey: FlutterPreferenceKeys.morningReminderMinute) as? Int ?? 0,
            eveningEnabled: defaults.bool(forKey: FlutterPreferenceKeys.eveningReminderEnabled),
            eveningHour: defaults.object(forKey: FlutterPreferenceKeys.eveningReminderHour) as? Int ?? 21,
            eveningMinute: defaults.object(forKey: FlutterPreferenceKeys.eveningReminderMinute) as? Int ?? 0
        )
    }

    func save(to defaults: UserDefaults?) {
        guard let defaults else { return }
        defaults.set(morningEnabled, forKey: FlutterPreferenceKeys.morningReminderEnabled)
        defaults.set(morningHour, forKey: FlutterPreferenceKeys.morningReminderHour)
        defaults.set(morningMinute, forKey: FlutterPreferenceKeys.morningReminderMinute)
        defaults.set(eveningEnabled, forKey: FlutterPreferenceKeys.eveningReminderEnabled)
        defaults.set(eveningHour, forKey: FlutterPreferenceKeys.eveningReminderHour)
        defaults.set(eveningMinute, forKey: FlutterPreferenceKeys.eveningReminderMinute)
    }

    /// Converts stored hour/minute into a `Date` for `DatePicker`, and back.
    func time(morning: Bool, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.hour = morning ? morningHour : eveningHour
        components.minute = morning ? morningMinute : eveningMinute
        return calendar.date(from: components) ?? Date()
    }

    mutating func setTime(_ date: Date, morning: Bool, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        if morning {
            morningHour = components.hour ?? morningHour
            morningMinute = components.minute ?? morningMinute
        } else {
            eveningHour = components.hour ?? eveningHour
            eveningMinute = components.minute ?? eveningMinute
        }
    }
}

#if canImport(EventKit)
@preconcurrency import EventKit
import Foundation

/// Also used by LiveActivityIntent in the host process. No permission prompt
/// is ever presented from an intent: permission is requested only in Settings.
@MainActor
public final class AppleRemindersClient {
    private let eventStore = EKEventStore()

    public init() {}

    public static var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    public func requestAccess() async throws -> Bool {
        if Self.hasAccess { return true }
        if #available(iOS 17.0, macOS 14.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        }
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .reminder) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    public struct List: Identifiable, Sendable {
        public let id: String
        public let title: String
    }

    public func lists() -> [List] {
        guard Self.hasAccess else { return [] }
        return eventStore.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { List(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public var defaultListID: String? {
        eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    public func fetch(selectedListIDs: Set<String>, knownIDs: Set<String>) async throws -> [AppleReminderRecord] {
        guard Self.hasAccess else { throw SyncError.accessRequired }
        // Re-fetch EventKit objects on each pass; changed notifications invalidate them.
        let calendars = eventStore.calendars(for: .reminder)
            .filter { selectedListIDs.contains($0.calendarIdentifier) && $0.allowsContentModifications }
        guard Set(calendars.map(\.calendarIdentifier)) == selectedListIDs else {
            throw SyncError.listUnavailable
        }
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: calendars
        )
        let incomplete: [AppleReminderRecord] = try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: SyncError.fetchFailed)
                    return
                }
                continuation.resume(returning: reminders.map(Self.record))
            }
        }
        try Task.checkCancellation()
        guard Self.hasAccess else { throw SyncError.accessRequired }
        let fetched = Set(incomplete.map(\.identifier))
        // Retain completed items already mirrored, without loading all historical completions.
        let completed = knownIDs.subtracting(fetched).compactMap { identifier -> AppleReminderRecord? in
            guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder,
                  selectedListIDs.contains(reminder.calendar.calendarIdentifier),
                  reminder.isCompleted else { return nil }
            return Self.record(reminder)
        }
        return incomplete + completed
    }

    /// Save Apple first. On denied access, read-only lists, deleted reminders,
    /// or device-lock errors, the caller must leave its checkbox unchanged.
    public static func setCompleted(
        identifier: String, isCompleted: Bool, store: AppGroupStore = AppGroupStore()
    ) throws {
        guard hasAccess else { throw SyncError.accessRequired }
        guard store.defaults?.bool(forKey: ReminderSyncPreferences.enabledKey) == true else {
            throw SyncError.disconnected
        }
        let eventStore = EKEventStore()
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw SyncError.reminderUnavailable
        }
        let selected = Set(store.defaults?.stringArray(forKey: ReminderSyncPreferences.calendarsKey) ?? [])
        guard selected.contains(reminder.calendar.calendarIdentifier) else { throw SyncError.disconnected }
        guard reminder.calendar.allowsContentModifications else { throw SyncError.readOnly }
        guard reminder.isCompleted != isCompleted else { return }
        reminder.isCompleted = isCompleted
        try eventStore.save(reminder, commit: true)
    }

    nonisolated private static func record(_ reminder: EKReminder) -> AppleReminderRecord {
        let dueDate = reminder.dueDateComponents.flatMap { components -> Date? in
            var calendar = components.calendar ?? Calendar.current
            if let zone = components.timeZone { calendar.timeZone = zone }
            return calendar.date(from: components)
        }
        return AppleReminderRecord(
            identifier: reminder.calendarItemIdentifier, title: reminder.title ?? "",
            dueDate: dueDate, isCompleted: reminder.isCompleted, completionDate: reminder.completionDate
        )
    }

    public enum SyncError: LocalizedError {
        case accessRequired, listUnavailable, fetchFailed, disconnected, reminderUnavailable, readOnly

        public var errorDescription: String? {
            let override = AppGroupStore().defaults?.string(forKey: "app.languageOverride")
            let language = (override == nil || override == "system")
                ? (Locale.preferredLanguages.first ?? "en") : (override ?? "en")
            let korean = language.hasPrefix("ko")
            switch self {
            case .accessRequired:
                return korean ? "설정에서 미리알림 접근을 허용한 뒤 다시 시도해주세요."
                    : "Allow Reminders access in Settings, then try again."
            case .listUnavailable:
                return korean ? "선택한 미리알림 목록을 사용할 수 없습니다. 목록을 다시 선택해주세요."
                    : "The selected Reminders lists are unavailable. Choose a list again."
            case .fetchFailed:
                return korean ? "미리알림을 가져오지 못했습니다. 기존 기록은 유지됩니다."
                    : "Reminders could not be loaded. Your existing items are preserved."
            case .disconnected:
                return korean ? "미리알림 연결이 해제되었습니다. 앱에서 연결 상태를 확인해주세요."
                    : "Reminders is disconnected. Check the connection in the app."
            case .reminderUnavailable:
                return korean ? "원본 미리알림을 찾을 수 없습니다. 앱에서 새로고침해주세요."
                    : "The original reminder is unavailable. Refresh in the app."
            case .readOnly:
                return korean ? "이 미리알림 목록은 변경할 수 없습니다."
                    : "This Reminders list cannot be modified."
            }
        }
    }
}
#endif

#if DEBUG
import Foundation
import SwiftUI
import EventKit
import LockTodoNoteShared

/// Explicit launch arguments only. No entitlement override or QA controls exist in Release.
@MainActor
enum DeviceQASupport {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-device-qa") }
    static var proOverride: Bool? {
        guard isEnabled, let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-qa-entitlement"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1) else { return nil }
        return ProcessInfo.processInfo.arguments[index + 1] == "pro"
    }
    private static let files = ["Data/cards.json", SmartLockScreenSchedule.profilesFileName, SmartLockScreenSchedule.fileName]
    private struct Archive: Codable { let preferences: Data; let files: [String: Data] }

    static func prepare(store: AppGroupStore) {
        guard isEnabled, let root = store.containerURL, let defaults = store.defaults else { return }
        let backup = root.appendingPathComponent("device-qa-backup-v1.json")
        do {
            if ProcessInfo.processInfo.arguments.contains("-device-qa-restore") {
                try cleanupReminders()
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: backup))
                let preferences = try PropertyListSerialization.propertyList(from: archive.preferences, format: nil) as! [String: Any]
                for key in (defaults.persistentDomain(forName: store.suiteName) ?? [:]).keys { defaults.removeObject(forKey: key) }
                for (key, value) in preferences { defaults.set(value, forKey: key) }
                for name in files {
                    let url = root.appendingPathComponent(name)
                    if let data = archive.files[name] { try data.write(to: url, options: .atomic) }
                    else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                }
                defaults.synchronize()
                try FileManager.default.removeItem(at: backup)
                return
            }
            if !FileManager.default.fileExists(atPath: backup.path) {
                let preferences = try PropertyListSerialization.data(
                    fromPropertyList: defaults.persistentDomain(forName: store.suiteName) ?? [:], format: .binary, options: 0
                )
                var contents: [String: Data] = [:]
                for name in files {
                    let url = root.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: url.path) { contents[name] = try Data(contentsOf: url) }
                }
                try JSONEncoder().encode(Archive(preferences: preferences, files: contents)).write(to: backup, options: .atomic)
            }
            if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
                for name in files where FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) {
                    try FileManager.default.removeItem(at: root.appendingPathComponent(name))
                }
            }
        } catch { fatalError("Device QA backup/restore failed: \(error)") }
    }

    static func seedIfRequested(store: AppGroupStore) {
        guard isEnabled else { return }
        if ProcessInfo.processInfo.arguments.contains("-device-qa-ads") {
            store.defaults?.set(true, forKey: FlutterPreferenceKeys.activationCompleted)
        }
        guard ProcessInfo.processInfo.arguments.contains("-device-qa-seed"), let root = store.containerURL else { return }
        let now = Date()
        let personal = Card(id: "qa-personal", title: "QA Personal", type: .checklist,
                            checklistItems: [ChecklistItem(id: "qa-personal-item", text: "QA Personal")],
                            targetDateTime: now, createdAt: now, updatedAt: now)
        let work = Card(id: "qa-work", title: "QA Work", type: .checklist,
                        checklistItems: [ChecklistItem(id: "qa-work-item", text: "QA Work")],
                        targetDateTime: now, createdAt: now, updatedAt: now)
        do {
            guard let cardURL = store.cardStoreURL else { return }
            try FileManager.default.createDirectory(at: cardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode([personal, work]).write(to: cardURL, options: .atomic)
            if ProcessInfo.processInfo.arguments.contains("-device-qa-timed") {
                let first = LayoutProfile(id: UUID(), name: "QA Morning", settings: LockScreenSettings(), colorTheme: "default")
                let second = LayoutProfile(id: UUID(), name: "QA Work", settings: LockScreenSettings(template: .dateTodo), colorTheme: "default")
                try JSONEncoder().encode([first, second]).write(to: root.appendingPathComponent(SmartLockScreenSchedule.profilesFileName), options: .atomic)
                let calendar = Calendar.current
                let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
                let boundary = (minute + 2) % 1440
                let rules = [
                    SmartLockScreenRule(name: "QA Before", profileID: first.id, weekdays: [1,2,3,4,5,6,7],
                                        startMinute: (boundary + 1430) % 1440, endMinute: boundary,
                                        todoSeriesIDs: ["qa-personal-item"], memoCardIDs: []),
                    SmartLockScreenRule(name: "QA After", profileID: second.id, weekdays: [1,2,3,4,5,6,7],
                                        startMinute: boundary, endMinute: (boundary + 1) % 1440,
                                        todoSeriesIDs: ["qa-work-item"], memoCardIDs: [])
                ]
                try JSONEncoder().encode(SmartLockScreenSchedule(isEnabled: true, rules: rules))
                    .write(to: root.appendingPathComponent(SmartLockScreenSchedule.fileName), options: .atomic)
            }
        } catch { fatalError("Device QA seed failed: \(error)") }
    }
}

struct DeviceQADiagnosticsView: View {
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var cards: CardStore
    @EnvironmentObject private var activity: LiveActivityService
    @EnvironmentObject private var ads: AdService
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
        Text("QA \(purchases.isPro ? "PRO" : "FREE") · \(dashboard.snapshot?.lockScreenLayout ?? "pending") · "
             + (dashboard.snapshot?.todoItems.map(\.text).joined(separator: " | ") ?? ""))
            .font(.system(size: 10)).padding(4).background(.regularMaterial)
            .accessibilityIdentifier("qa.dashboard")
        Text("QA Ads: eligible=\(ads.isEligible) ready=\(ads.isReady) event=\(ads.qaLastEvent)")
            .font(.system(size: 9)).accessibilityIdentifier("qa.ads")
        Text("QA Activity: \(activity.state.analyticsName)")
            .font(.system(size: 9)).accessibilityIdentifier("qa.activity")
        Text("QA storage: \(cards.cards.count) cards")
            .font(.system(size: 9))
            .accessibilityIdentifier("qa.storage")
            .accessibilityValue((try? JSONEncoder().encode(cards.cards)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]")
        }
        .allowsHitTesting(false)
    }
}
#endif

#if DEBUG
@MainActor
extension DeviceQASupport {
    struct ReminderRecord: Codable { let calendarID: String; let reminderID: String }
    static var reminderRecordsURL: URL? { AppGroupStore().containerURL?.appendingPathComponent("device-qa-reminders.json") }

    static func createReminder() async throws -> ReminderRecord {
        guard try await AppleRemindersClient().requestAccess() else { throw AppleRemindersClient.SyncError.accessRequired }
        let events = EKEventStore()
        guard let source = events.defaultCalendarForNewReminders()?.source
            ?? events.sources.first(where: { $0.sourceType == .local }) else { throw AppleRemindersClient.SyncError.listUnavailable }
        let calendar = EKCalendar(for: .reminder, eventStore: events)
        calendar.title = "[LockTodoNote QA] \(UUID().uuidString.prefix(8))"
        calendar.source = source
        try events.saveCalendar(calendar, commit: true)
        let reminder = EKReminder(eventStore: events)
        reminder.title = "QA Apple Reminder"
        reminder.calendar = calendar
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        try events.save(reminder, commit: true)
        let record = ReminderRecord(calendarID: calendar.calendarIdentifier, reminderID: reminder.calendarItemIdentifier)
        if let url = reminderRecordsURL {
            var records = (try? JSONDecoder().decode([ReminderRecord].self, from: Data(contentsOf: url))) ?? []
            records.append(record)
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        }
        return record
    }

    static func cleanupReminders() throws {
        guard let url = reminderRecordsURL, FileManager.default.fileExists(atPath: url.path) else { return }
        let records = try JSONDecoder().decode([ReminderRecord].self, from: Data(contentsOf: url))
        let events = EKEventStore()
        for record in records {
            if let calendar = events.calendar(withIdentifier: record.calendarID), calendar.title.hasPrefix("[LockTodoNote QA]") {
                try events.removeCalendar(calendar, commit: true)
            }
        }
        try FileManager.default.removeItem(at: url)
    }
}

struct DeviceQAReminderControls: View {
    @EnvironmentObject private var sync: ReminderSyncService
    @State private var record: DeviceQASupport.ReminderRecord?
    @State private var status = "QA ready"
    var body: some View {
        Section("Device QA — real EventKit") {
            Button("QA Create Apple Reminder") {
                Task {
                    do {
                        let value = try await DeviceQASupport.createReminder()
                        record = value
                        await sync.connect()
                        for identifier in sync.selectedListIDs where identifier != value.calendarID {
                            await sync.setList(identifier, selected: false)
                        }
                        sync.refreshLists()
                        await sync.setList(value.calendarID, selected: true)
                        status = "QA imported"
                    } catch { status = "QA error: \(error.localizedDescription)" }
                }
            }.accessibilityIdentifier("qa.reminder.create")
            Button("QA Verify Apple Source") {
                let saved = DeviceQASupport.reminderRecordsURL.flatMap { try? Data(contentsOf: $0) }
                    .flatMap { try? JSONDecoder().decode([DeviceQASupport.ReminderRecord].self, from: $0) }?.last
                guard let record = record ?? saved,
                      let reminder = EKEventStore().calendarItem(withIdentifier: record.reminderID) as? EKReminder else {
                    status = "QA missing source"; return
                }
                status = reminder.isCompleted ? "QA source completed" : "QA source pending"
            }.accessibilityIdentifier("qa.reminder.verify")
            Text(status).accessibilityIdentifier("qa.reminder.status")
        }
    }
}
#endif

import ActivityKit
import AppIntents
import Foundation
import WidgetKit
import LockTodoNoteShared

// MARK: - Public intents

/// The one capture intent users see in the Shortcuts app.
@available(iOS 16.2, iOSApplicationExtension 16.2, *)
struct AddToLockTodoNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to LockTodoNote"
    static let description = IntentDescription("Add a memo or todo to LockTodoNote.")
    static let isDiscoverable: Bool = true
    static let openAppWhenRun = false

    @Parameter(title: "Text", requestValueDialog: "What do you want to add?")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Self.reply(.emptyText)
        }

        let store = AppGroupStore()
        guard let defaults = store.defaults else {
            return Self.reply(.failed)
        }

        // Pro is read from the published dashboard state; the extension cannot
        // reach StoreKit.
        let isPro = store.dashboardState()?["isPro"] as? Bool ?? false
        if !isPro, store.shortcutUsageCount() >= AppGroupKeys.freeShortcutDailyLimit {
            return Self.reply(.limitReached)
        }

        let settings = LockScreenSettings.load(from: defaults)
        let target = settings.resolveShortcutTarget()
        let dateKey = ShortcutSupport.selectedDateKey(store: store)
        let id = "shortcut-\(Int(Date().timeIntervalSince1970 * 1_000_000))"

        store.appendPendingQuickAdd(
            PendingQuickAdd(
                id: id,
                text: trimmed,
                target: target,
                dateKey: dateKey,
                createdAt: Date()
            )
        )
        // Counted once, here. The Flutter build also counted it again inside the
        // app against a separate key, so the two could disagree.
        if !isPro { store.recordShortcutUsage() }

        ShortcutSupport.applyQuickAddToDashboard(
            id: id,
            text: trimmed,
            target: target,
            dateKey: dateKey,
            store: store
        )
        await ShortcutSupport.refreshActivities(store: store, source: "shortcut")

        store.enqueueAnalyticsEvent(
            name: "shortcut_quick_add",
            parameters: [
                "source": "shortcut",
                "target": target.rawValue,
                "template_id": settings.template.rawValue,
                "is_premium": isPro,
                "result": "success",
            ]
        )
        ReviewEligibilityRecorder(store: store).record(
            target == .memo ? .memoCreated(1) : .todoCreated(1),
            trigger: "shortcut_quick_add"
        )
        return Self.reply(target == .memo ? .addedToMemo : .addedToTodo)
    }

    private enum Reply {
        case emptyText, limitReached, addedToTodo, addedToMemo, failed

        var message: String {
            switch self {
            case .emptyText:
                localized("intent.emptyText", defaultValue: "Text is empty")
            case .limitReached:
                localized(
                    "intent.limitReached",
                    defaultValue: "You've used all free Shortcut adds today. Upgrade to Pro for unlimited adds."
                )
            case .addedToTodo:
                localized("intent.addedToTodo", defaultValue: "Added to Todo")
            case .addedToMemo:
                localized("intent.addedToMemo", defaultValue: "Added to Memo")
            case .failed:
                localized("intent.failed", defaultValue: "Could not save that.")
            }
        }
    }

    private static func reply(
        _ reply: Reply
    ) -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        .result(value: reply.message, dialog: IntentDialog(stringLiteral: reply.message))
    }
}

/// Restarts the Live Activity after iOS has let it go stale.
@available(iOS 16.2, iOSApplicationExtension 16.2, *)
struct RefreshLockScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Lock Screen"
    static let description = IntentDescription("Restart the LockTodoNote Live Activity.")
    static let isDiscoverable: Bool = true
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppGroupStore()
        let refreshed = try await ShortcutSupport.restartActivity(store: store)
        if refreshed {
            ReviewEligibilityRecorder(store: store).record(
                .liveActivitySuccess,
                trigger: "live_activity_restarted"
            )
        }
        let message = refreshed
            ? localized("intent.refreshed", defaultValue: "Refreshed the Lock Screen")
            : localized(
                "intent.setupFirst",
                defaultValue: "Set up the Lock Screen in the app first"
            )
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

@available(iOS 16.2, iOSApplicationExtension 16.2, *)
struct LockTodoNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToLockTodoNoteIntent(),
            phrases: [
                "Add to \(.applicationName)",
            ],
            shortTitle: "Add to LockTodoNote",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: RefreshLockScreenIntent(),
            phrases: [
                "Refresh \(.applicationName)",
            ],
            shortTitle: "Refresh Lock Screen",
            systemImageName: "arrow.clockwise"
        )
    }
}

// MARK: - Live Activity button intents (not user-visible)

@available(iOS 16.2, iOSApplicationExtension 16.2, *)
struct ToggleTodoIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete todo"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Todo ID") var todoId: String
    @Parameter(title: "Completion Source") var completionSource: String

    init() {}

    init(todoId: String, source: String = "live_activity") {
        self.todoId = todoId
        self.completionSource = source
    }

    func perform() async throws -> some IntentResult {
        let store = AppGroupStore()
        guard var payload = store.dashboardState() else { return .result() }

        store.appendPendingCompletedTodo(
            PendingCompletedTodo(id: todoId, completedAt: Date(), source: completionSource)
        )
        ShortcutSupport.completeTodo(todoId, in: &payload)
        store.saveDashboardState(payload)
        await ShortcutSupport.updateActivities(with: payload)

        ReviewEligibilityRecorder(store: store).record(
            .todoCompleted(lockScreenInteraction: true),
            trigger: completionSource == "widget" ? "widget_todo_completed" : "todo_completed"
        )
        var analyticsParameters = ShortcutSupport.analyticsParameters(
            from: payload,
            source: completionSource
        )
        analyticsParameters["review_signal_recorded"] = true

        store.enqueueAnalyticsEvent(
            name: "todo_completed",
            parameters: analyticsParameters
        )
        if completionSource == "widget" {
            store.enqueueAnalyticsEvent(
                name: "widget_todo_completed",
                parameters: analyticsParameters
            )
        } else if completionSource == "dynamic_island" {
            store.enqueueAnalyticsEvent(
                name: "dynamic_island_interacted",
                parameters: analyticsParameters
            )
        }
        return .result()
    }
}

@available(iOS 16.2, iOSApplicationExtension 16.2, *)
struct SelectDateIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Select date"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Date") var dateString: String

    init() {}
    init(dateString: String) { self.dateString = dateString }

    func perform() async throws -> some IntentResult {
        let store = AppGroupStore()
        guard var payload = store.dashboardState() else { return .result() }
        ShortcutSupport.selectDate(dateString, in: &payload)
        // No widget reload here: only the activity's selection changed.
        store.saveDashboardState(payload, reloadWidget: false)
        await ShortcutSupport.updateActivities(with: payload)
        return .result()
    }
}

@available(iOS 16.2, iOSApplicationExtension 16.2, *)
struct SelectContentSectionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Select content section"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Section") var section: String

    init() {}
    init(section: String) { self.section = section }

    func perform() async throws -> some IntentResult {
        let store = AppGroupStore()
        guard var payload = store.dashboardState() else { return .result() }
        let selectedSection = section == "memo" ? "memo" : "todo"
        payload["selectedContentSection"] = selectedSection
        store.defaults?.set(
            selectedSection,
            forKey: FlutterPreferenceKeys.selectedContentSection
        )
        payload["updatedAt"] = Date().timeIntervalSince1970
        store.saveDashboardState(payload, reloadWidget: false)
        await ShortcutSupport.updateActivities(with: payload)
        return .result()
    }
}

// MARK: - Shared helpers

@available(iOS 16.2, iOSApplicationExtension 16.2, *)
enum ShortcutSupport {
    static func selectedDateKey(store: AppGroupStore) -> String {
        guard
            let raw = store.dashboardState()?["selectedDate"] as? String,
            let date = FlutterDate.date(fromKey: raw)
        else {
            return FlutterDate.dateKey(Date())
        }
        return FlutterDate.dateKey(date)
    }

    /// Optimistically reflects the capture on the Lock Screen. The app performs
    /// the authoritative write when it next opens and drains the queue.
    static func applyQuickAddToDashboard(
        id: String,
        text: String,
        target: ShortcutInsertPriority,
        dateKey: String,
        store: AppGroupStore
    ) {
        var payload = store.dashboardState() ?? [:]
        payload["selectedDate"] = dateKey
        payload["selectedDateText"] = dateKey

        switch target {
        case .todo:
            // Must match the id the app builds when it merges the queue.
            let item: [String: Any] = ["id": "\(id):\(id)-item-0", "text": text, "isDone": false]
            var todos = payload["todoItems"] as? [[String: Any]] ?? []
            todos.insert(item, at: 0)
            payload["todoItems"] = Array(todos.prefix(5))
            payload["totalCount"] = ((payload["totalCount"] as? NSNumber)?.intValue ?? 0) + 1
            insertCalendarItem(item, key: "todoItems", dateKey: dateKey, in: &payload)
        case .memo:
            let item: [String: Any] = [
                "id": id,
                "title": CardMutations.memoTitle(from: text),
                "bodyPreview": String(text.prefix(42)),
            ]
            var memos = payload["memoItems"] as? [[String: Any]] ?? []
            memos.insert(item, at: 0)
            payload["memoItems"] = Array(memos.prefix(2))
            payload["memoTitle"] = item["title"]
            payload["memoText"] = text
            payload["memoId"] = id
            insertCalendarItem(item, key: "memoItems", dateKey: dateKey, in: &payload)
        }
        payload["updatedAt"] = Date().timeIntervalSince1970
        store.saveDashboardState(payload)
    }

    private static func insertCalendarItem(
        _ item: [String: Any],
        key: String,
        dateKey: String,
        in payload: inout [String: Any]
    ) {
        var days = payload["calendarDays"] as? [[String: Any]] ?? []
        guard let index = days.firstIndex(where: { $0["id"] as? String == dateKey }) else { return }
        var items = days[index][key] as? [[String: Any]] ?? []
        items.insert(item, at: 0)
        days[index][key] = items
        days[index]["hasItems"] = true
        payload["calendarDays"] = days
    }

    static func completeTodo(_ todoId: String, in payload: inout [String: Any]) {
        let before = remainingCount(payload["todoItems"])

        // A completed item should leave the glance surface immediately. The
        // authoritative card still keeps its completion state for app history.
        payload["todoItems"] = remove(todoId, from: payload["todoItems"])

        var days = payload["calendarDays"] as? [[String: Any]] ?? []
        for index in days.indices {
            days[index]["todoItems"] = remove(todoId, from: days[index]["todoItems"])
            let todos = days[index]["todoItems"] as? [[String: Any]] ?? []
            let memos = days[index]["memoItems"] as? [[String: Any]] ?? []
            days[index]["hasItems"] = !todos.isEmpty || !memos.isEmpty
        }
        payload["calendarDays"] = days

        if remainingCount(payload["todoItems"]) < before {
            payload["doneCount"] = ((payload["doneCount"] as? NSNumber)?.intValue ?? 0) + 1
        }
        payload["updatedAt"] = Date().timeIntervalSince1970
    }

    static func selectDate(_ dateKey: String, in payload: inout [String: Any]) {
        var days = payload["calendarDays"] as? [[String: Any]] ?? []
        guard let selectedIndex = days.firstIndex(where: { $0["id"] as? String == dateKey }) else { return }
        for index in days.indices {
            days[index]["isSelected"] = index == selectedIndex
        }
        let selected = days[selectedIndex]
        payload["calendarDays"] = days
        payload["selectedDate"] = dateKey
        payload["selectedDateText"] = selected["id"] as? String

        let todos = selected["todoItems"] as? [[String: Any]] ?? []
        payload["totalCount"] = todos.count
        payload["doneCount"] = todos.filter { $0["isDone"] as? Bool ?? false }.count

        if payload["showTodosOnLockScreen"] as? Bool ?? true {
            let showCompleted = payload["showCompletedTodosOnLockScreen"] as? Bool ?? true
            payload["todoItems"] = showCompleted ? todos : todos.filter { !($0["isDone"] as? Bool ?? false) }
        } else {
            payload["todoItems"] = []
        }
        payload["memoItems"] = (payload["showMemosOnLockScreen"] as? Bool ?? true)
            ? (selected["memoItems"] as? [[String: Any]] ?? [])
            : []
        payload["updatedAt"] = Date().timeIntervalSince1970
    }

    private static func markDone(_ todoId: String, in value: Any?) -> [[String: Any]] {
        (value as? [[String: Any]] ?? []).map { row in
            guard row["id"] as? String == todoId else { return row }
            var updated = row
            updated["isDone"] = true
            return updated
        }
    }

    private static func remove(_ todoId: String, from value: Any?) -> [[String: Any]] {
        (value as? [[String: Any]] ?? []).filter { $0["id"] as? String != todoId }
    }

    private static func remainingCount(_ value: Any?) -> Int {
        (value as? [[String: Any]] ?? []).filter { !($0["isDone"] as? Bool ?? false) }.count
    }

    // MARK: Activity refresh

    static func updateActivities(with payload: [String: Any]) async {
        let state = GlanceDashboardAttributes.ContentState(snapshot: DashboardSnapshot(dictionary: payload))
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(8 * 60 * 60))
        for activity in Activity<GlanceDashboardAttributes>.activities {
            await activity.update(content)
        }
    }

    static func refreshActivities(store: AppGroupStore, source: String) async {
        guard let payload = store.dashboardState() else { return }
        await updateActivities(with: payload)
        store.enqueueAnalyticsEvent(
            name: "lockscreen_activity_updated",
            parameters: analyticsParameters(from: payload, source: source)
        )
    }

    /// Ends and restarts the activity, which is the only way to clear a stale
    /// one without opening the app.
    static func restartActivity(store: AppGroupStore) async throws -> Bool {
        guard var payload = store.dashboardState(), !payload.isEmpty else { return false }
        payload["updatedAt"] = Date().timeIntervalSince1970
        store.saveDashboardState(payload)

        for activity in Activity<GlanceDashboardAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let snapshot = DashboardSnapshot(dictionary: payload)
        _ = try Activity.request(
            attributes: GlanceDashboardAttributes(
                dashboardId: payload["dashboardId"] as? String ?? AppGroupKeys.liveActivityDashboardId
            ),
            content: ActivityContent(
                state: .init(snapshot: snapshot),
                staleDate: Date().addingTimeInterval(8 * 60 * 60)
            ),
            pushType: nil
        )
        store.enqueueAnalyticsEvent(
            name: "lockscreen_activity_updated",
            parameters: analyticsParameters(from: payload, source: "shortcut")
        )
        var restartedParameters = analyticsParameters(from: payload, source: "shortcut")
        restartedParameters["review_signal_recorded"] = true
        store.enqueueAnalyticsEvent(
            name: "live_activity_restarted",
            parameters: restartedParameters
        )
        return true
    }

    static func analyticsParameters(from payload: [String: Any], source: String) -> [String: Any] {
        let todos = payload["todoItems"] as? [[String: Any]] ?? []
        let total = (payload["totalCount"] as? NSNumber)?.intValue ?? todos.count
        let remaining = todos.filter { !($0["isDone"] as? Bool ?? false) }.count
        return [
            "source": source,
            "screen_name": "lockscreen",
            "task_count": total,
            "todo_count": total,
            "remaining_count": remaining,
            "completed_count": max(0, total - remaining),
            "has_memo": !(payload["memoItems"] as? [[String: Any]] ?? []).isEmpty,
            "template_id": payload["lockScreenLayout"] as? String ?? "",
            "setup_type": "live_activity",
            "live_activity_enabled": true,
            "ios_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "device_family": "ios_activity_extension",
            "is_premium": payload["isPro"] as? Bool ?? false,
            "result": "success",
        ]
    }
}

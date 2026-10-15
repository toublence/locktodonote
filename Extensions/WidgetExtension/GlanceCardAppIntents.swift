import ActivityKit
import AppIntents
import Foundation
import WidgetKit
import LockTodoNoteShared

// MARK: - Public intents

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public enum QuickAddTarget: String, AppEnum {
    case todo
    case memo

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Type")
    public static let caseDisplayRepresentations: [QuickAddTarget: DisplayRepresentation] = [
        .todo: DisplayRepresentation(
            title: LocalizedStringResource("quickAdd.target.todo", defaultValue: "Todo")
        ),
        .memo: DisplayRepresentation(
            title: LocalizedStringResource("quickAdd.target.memo", defaultValue: "Memo")
        ),
    ]
}

/// The core Quick Add intent users run from Shortcuts, Siri, Action Button, and Lock Screen.
@available(iOS 16.2, iOSApplicationExtension 16.2, *)
struct AddToLockTodoNoteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = LocalizedStringResource(
        "intent.addToLockTodoNote.title",
        defaultValue: "Add to LockTodoNote"
    )
    static let description = IntentDescription(
        LocalizedStringResource(
            "intent.addToLockTodoNote.description",
            defaultValue: "Quickly add a todo or note without opening the app."
        )
    )
    static let isDiscoverable: Bool = true
    static let openAppWhenRun = false

    @Parameter(title: "Text", default: "")
    var text: String

    @Parameter(title: "Type", default: nil)
    var target: QuickAddTarget?

    @Parameter(title: "Date")
    var date: Date?

    @Parameter(title: "Smart date recognition", default: true)
    var smartRecognition: Bool

    @Parameter(title: "Source", default: "unknown")
    var source: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = AppGroupStore()
        guard let defaults = store.defaults else {
            return Self.reply(.failed)
        }

        let settings = LockScreenSettings.load(from: defaults)
        let isPro = store.dashboardState()?["isPro"] as? Bool ?? false
        let safeSource = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : source

        // Check daily limit before prompting user for text
        if !isPro, store.shortcutUsageCount() >= AppGroupKeys.freeShortcutDailyLimit {
            defaults.set(true, forKey: AppGroupKeys.shortcutLimitReached)
            store.enqueueAnalyticsEvent(
                name: "quick_add_limit_reached",
                parameters: [
                    "daily_count": store.shortcutUsageCount(),
                    "source": safeSource
                ]
            )
            store.enqueueAnalyticsEvent(
                name: "quick_add_failed",
                parameters: [
                    "reason": "daily_limit",
                    "source": safeSource
                ]
            )
            return Self.reply(.limitReached)
        }

        store.enqueueAnalyticsEvent(
            name: "quick_add_invoked",
            parameters: [
                "source": safeSource,
                "selected_template": settings.template.rawValue,
                "is_pro": isPro
            ]
        )

        // Resolve Target (Todo vs Memo)
        let resolvedTarget: ShortcutInsertPriority
        if let target {
            resolvedTarget = (target == .memo) ? .memo : .todo
        } else if settings.template.isTodoOnly {
            resolvedTarget = .todo
        } else if settings.template.isMemoOnly {
            resolvedTarget = .memo
        } else {
            // Mixed template: check if user configured a default in Settings > Shortcuts
            if defaults.object(forKey: FlutterPreferenceKeys.shortcutInsertPriority) != nil {
                resolvedTarget = settings.shortcutInsertPriority
            } else {
                let chosen = try await $target.requestDisambiguation(
                    among: [.todo, .memo],
                    dialog: IntentDialog(stringLiteral: localized("intent.promptTarget", defaultValue: "What do you want to add?"))
                )
                resolvedTarget = (chosen == .memo) ? .memo : .todo
                store.enqueueAnalyticsEvent(
                    name: "quick_add_type_selected",
                    parameters: [
                        "type": resolvedTarget.rawValue,
                        "source": safeSource
                    ]
                )
            }
        }

        // Resolve Content Text
        var content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            content = try await $text.requestValue(
                IntentDialog(stringLiteral: localized("intent.promptText", defaultValue: "What do you want to add?"))
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !content.isEmpty else {
            store.enqueueAnalyticsEvent(
                name: "quick_add_failed",
                parameters: [
                    "reason": "empty_text",
                    "source": safeSource
                ]
            )
            return Self.reply(.emptyText)
        }

        let capturedAt = Date()
        let effectiveDate = date ?? capturedAt
        let smartTodos: [SmartTodo]? = resolvedTarget == .todo
            ? SmartQuickAddParser.parse(
                content, referenceDate: capturedAt, defaultDate: effectiveDate,
                explicitDate: date, enabled: smartRecognition
            ) : nil
        let dateKey = FlutterDate.dateKey(smartTodos?.first?.scheduledDate ?? effectiveDate)
        let id = "shortcut-\(Int(capturedAt.timeIntervalSince1970 * 1_000_000))"

        let itemCount: Int
        if resolvedTarget == .todo {
            let lines = QuickCaptureService.parseTodoLines(from: content)
            guard !lines.isEmpty else {
                store.enqueueAnalyticsEvent(
                    name: "quick_add_failed",
                    parameters: ["reason": "empty_text", "source": safeSource]
                )
                return Self.reply(.emptyText)
            }
            itemCount = lines.count
        } else {
            itemCount = 1
        }

        store.appendPendingQuickAdd(
            PendingQuickAdd(
                id: id,
                text: content,
                target: resolvedTarget,
                dateKey: dateKey,
                createdAt: capturedAt,
                smartTodos: smartTodos
            )
        )
        if !isPro { store.recordShortcutUsage() }

        ShortcutSupport.applyQuickAddToDashboard(
            id: id,
            text: content,
            target: resolvedTarget,
            dateKey: dateKey,
            smartTodos: smartTodos,
            store: store
        )

        let activityUpdated = await ShortcutSupport.refreshActivities(store: store, source: safeSource)
        if !activityUpdated {
            store.enqueueAnalyticsEvent(
                name: "quick_add_failed",
                parameters: [
                    "reason": "live_activity_update_failed",
                    "source": safeSource
                ]
            )
        }

        store.enqueueAnalyticsEvent(
            name: "shortcut_quick_add",
            parameters: [
                "type": resolvedTarget.rawValue,
                "target": resolvedTarget.rawValue,
                "item_count": itemCount,
                "source": safeSource,
                "selected_template": settings.template.rawValue,
                "template_id": settings.template.rawValue,
                "is_pro": isPro,
                "is_premium": isPro,
                "result": "success",
            ]
        )
        store.markQuickAddEducationCompleted()
        store.enqueueAnalyticsEvent(
            name: "quick_add_education_completed",
            parameters: ["source": safeSource]
        )

        ReviewEligibilityRecorder(store: store).record(
            resolvedTarget == .memo ? .memoCreated(1) : .todoCreated(itemCount),
            trigger: "shortcut_quick_add"
        )

        return Self.reply(resolvedTarget == .memo ? .addedToMemo : .addedToTodo(count: itemCount))
    }

    private enum Reply {
        case emptyText, limitReached, addedToTodo(count: Int), addedToMemo, failed

        var message: String {
            switch self {
            case .emptyText:
                return localized("intent.emptyText", defaultValue: "Text is empty")
            case .limitReached:
                return localized(
                    "intent.limitReached",
                    defaultValue: "You've used all free Quick Adds for today. LockTodoNote Pro includes unlimited Quick Add."
                )
            case .addedToTodo(let count):
                if count <= 1 {
                    return localized("intent.addedToTodo", defaultValue: "Todo added.")
                } else {
                    let format = localized("intent.multipleTodosAdded", defaultValue: "%d todos added.")
                    return String(format: format, count)
                }
            case .addedToMemo:
                return localized("intent.addedToMemo", defaultValue: "Note added.")
            case .failed:
                return localized("intent.failed", defaultValue: "Could not save that.")
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
struct RefreshLockScreenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh Lock Screen"
    static let description = IntentDescription("Restart the LockTodoNote Live Activity.")
    static let isDiscoverable: Bool = true
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppGroupStore()
        let requestId = UUID().uuidString
        let refreshed: Bool
        do {
            refreshed = try await ShortcutSupport.restartActivity(store: store, requestId: requestId)
        } catch {
            store.enqueueAnalyticsEvent(
                name: "live_activity_start_failed",
                parameters: [
                    "source": "shortcut", "request_id": requestId,
                    "reason": "activity_request_failed", "result": "fail",
                ]
            )
            return .result(dialog: IntentDialog(stringLiteral: localized(
                "intent.refreshFailed",
                defaultValue: "The Lock Screen could not be refreshed. Open the app and try again."
            )))
        }
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
                "Add a todo to \(.applicationName)",
                "Add a note to \(.applicationName)",
                "\(.applicationName)에 추가",
                "\(.applicationName) 할 일 추가",
                "\(.applicationName) 메모 추가",
            ],
            shortTitle: LocalizedStringResource("shortcuts.add.shortTitle", defaultValue: "Add to LockTodoNote"),
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: RefreshLockScreenIntent(),
            phrases: [
                "Refresh \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("shortcuts.refresh.shortTitle", defaultValue: "Refresh Lock Screen"),
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
        guard !todoId.hasPrefix("projected:") else { return .result() }
        let scheduled = (try? SmartLockScreenSchedule.load(store: store))?.isEnabled == true
        guard var payload = (scheduled ? ShortcutSupport.rebuiltDashboardPayload(store: store, previewOnly: true) : nil)
            ?? store.dashboardState() else { return .result() }
        let occurredAt = Date()
        let eventId = UUID().uuidString

        if let cardID = todoId.split(separator: ":", maxSplits: 1).first,
           let identifier = AppleReminderMirror.reminderID(from: String(cardID)) {
            try await MainActor.run {
                try AppleRemindersClient.setCompleted(identifier: identifier, isCompleted: true, store: store)
            }
        }
        store.appendPendingCompletedTodo(
            PendingCompletedTodo(
                id: todoId,
                completedAt: occurredAt,
                source: completionSource,
                eventId: eventId
            )
        )
        ShortcutSupport.completeTodo(todoId, in: &payload)
        store.saveDashboardState(payload)
        await ShortcutSupport.updateActivities(with: payload)
        store.postDataChangedNotification()

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
            parameters: analyticsParameters,
            eventId: eventId,
            createdAt: occurredAt
        )
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
        store.defaults?.set(false, forKey: FlutterPreferenceKeys.followToday)
        // No widget reload here: only the activity's selection changed.
        store.saveDashboardState(payload, reloadWidget: false)
        await ShortcutSupport.updateActivities(with: payload)
        store.enqueueAnalyticsEvent(
            name: "lockscreen_interacted",
            parameters: ["source": "live_activity", "surface": "live_activity", "action": "select_date", "result": "success"]
        )
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
        store.enqueueAnalyticsEvent(
            name: "lockscreen_interacted",
            parameters: ["source": "live_activity", "surface": "live_activity", "action": "select_content", "result": "success"]
        )
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
        smartTodos: [SmartTodo]? = nil,
        store: AppGroupStore
    ) {
        let scheduled = (try? SmartLockScreenSchedule.load(store: store))?.isEnabled == true
        if scheduled {
            if let rebuilt = rebuiltDashboardPayload(store: store, previewOnly: true) { store.saveDashboardState(rebuilt) }
            return
        }
        if target == .todo, smartTodos != nil,
           let rebuilt = rebuiltDashboardPayload(
               store: store, selectedDateOverride: smartTodos?.first?.scheduledDate
           ) {
            store.saveDashboardState(rebuilt)
            return
        }
        var payload = store.dashboardState() ?? [:]
        let previousDate = payload["selectedDate"] as? String
        payload["selectedDate"] = dateKey
        payload["selectedDateText"] = dateKey

        switch target {
        case .todo:
            let rows = smartTodos ?? SmartQuickAddParser.parse(
                text, defaultDate: FlutterDate.date(fromKey: dateKey), enabled: false
            )
            guard !rows.isEmpty else { return }
            let days = payload["calendarDays"] as? [[String: Any]] ?? []
            var todos = previousDate == dateKey
                ? (payload["todoItems"] as? [[String: Any]] ?? [])
                : (days.first { $0["id"] as? String == dateKey }?["todoItems"] as? [[String: Any]] ?? [])
            var addedOnSelectedDay = 0
            for (index, row) in rows.enumerated().reversed() {
                let cardId = rows.count == 1 ? id : "\(id)-\(index)"
                let itemId = "\(cardId)-item-0"
                let compositeId = "\(cardId):\(itemId)"
                let title = ChecklistItem(
                    id: itemId, text: row.text, dueDate: row.dueDate, hasDueTime: row.hasDueTime
                ).displayText()
                let item: [String: Any] = ["id": compositeId, "text": title, "isDone": false]
                let itemDay = FlutterDate.dateKey(row.scheduledDate)
                if itemDay == dateKey {
                    todos.insert(item, at: 0)
                    addedOnSelectedDay += 1
                }
                insertCalendarItem(item, key: "todoItems", dateKey: itemDay, in: &payload)
            }
            payload["todoItems"] = Array(todos.prefix(5))
            payload["totalCount"] = previousDate == dateKey
                ? ((payload["totalCount"] as? NSNumber)?.intValue ?? 0) + addedOnSelectedDay : todos.count
            if previousDate != dateKey {
                payload["doneCount"] = todos.filter { $0["isDone"] as? Bool == true }.count
            }
        case .memo:
            let cleaned = QuickCaptureService.cleanMemoText(from: text)
            guard !cleaned.isEmpty else { return }
            let item: [String: Any] = [
                "id": id,
                "title": CardMutations.memoTitle(from: cleaned),
                "bodyPreview": String(cleaned.prefix(42)),
            ]
            var memos = payload["memoItems"] as? [[String: Any]] ?? []
            memos.insert(item, at: 0)
            payload["memoItems"] = Array(memos.prefix(2))
            payload["memoTitle"] = item["title"]
            payload["memoText"] = cleaned
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

    @discardableResult
    static func refreshActivities(store: AppGroupStore, source: String) async -> Bool {
        let scheduled = (try? SmartLockScreenSchedule.load(store: store))?.isEnabled == true
        guard let payload = (scheduled ? rebuiltDashboardPayload(store: store, previewOnly: true) : nil)
            ?? store.dashboardState() else { return false }
        store.saveDashboardState(payload)
        await updateActivities(with: payload)
        store.enqueueAnalyticsEvent(
            name: "lockscreen_activity_updated",
            parameters: analyticsParameters(from: payload, source: source)
        )
        return true
    }

    /// Ends and restarts the activity, which is the only way to clear a stale
    /// one without opening the app.
    static func restartActivity(store: AppGroupStore, requestId: String) async throws -> Bool {
        guard let payload = rebuiltDashboardPayload(store: store, previewOnly: true) else { return false }
        store.saveDashboardState(payload)

        var attemptParameters = analyticsParameters(from: payload, source: "shortcut")
        attemptParameters["request_id"] = requestId
        attemptParameters["reason"] = "user_refresh"
        store.enqueueAnalyticsEvent(
            name: "live_activity_start_attempt",
            parameters: attemptParameters
        )

        // Keep the existing card if requesting its replacement fails.
        let previousActivities = Activity<GlanceDashboardAttributes>.activities
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
        for activity in previousActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        store.defaults?.set(false, forKey: FlutterPreferenceKeys.explicitlyStoppedLiveActivity)
        store.defaults?.set(true, forKey: FlutterPreferenceKeys.liveActivityStarted)
        store.defaults?.set(Date().timeIntervalSince1970, forKey: AppGroupKeys.liveActivityStartedAt)
        store.defaults?.removeObject(forKey: AppGroupKeys.liveActivityStaleLogged)
        store.enqueueAnalyticsEvent(
            name: "lockscreen_activity_updated",
            parameters: analyticsParameters(from: payload, source: "shortcut")
        )
        var successParameters = analyticsParameters(from: payload, source: "shortcut")
        successParameters["request_id"] = requestId
        store.enqueueAnalyticsEvent(
            name: "live_activity_start_success",
            parameters: successParameters
        )
        var restartedParameters = analyticsParameters(from: payload, source: "shortcut")
        restartedParameters["review_signal_recorded"] = true
        store.enqueueAnalyticsEvent(
            name: "live_activity_restarted",
            parameters: restartedParameters
        )
        return true
    }

    /// Rebuilds from durable cards plus unacknowledged extension work. A stale
    /// dashboard payload is never used as the source of a new activity.
    static func rebuiltDashboardPayload(
        store: AppGroupStore, now: Date = Date(), selectedDateOverride: Date? = nil, previewOnly: Bool = false
    ) -> [String: Any]? {
        guard let url = store.cardStoreURL,
              let data = try? Data(contentsOf: url),
              var cards = try? JSONDecoder().decode([Card].self, from: data)
        else { return nil }

        cards = CardMutations.applyQuickAdds(store.pendingQuickAdds(), to: cards).cards
        cards = CardMutations.applyCompletions(store.pendingCompletedTodos(), to: cards, now: now).cards
        let existingIDs = Set(cards.map(\.id))
        cards = CardMutations.rollOverIncompleteTodos(cards, now: now).cards
        cards = CardMutations.createRecurringTodosForToday(cards, now: now).cards
        if previewOnly {
            // Read-only future occurrences do not have durable completion IDs yet.
            // Tapping them opens the app, which materializes the real occurrence.
            cards = cards.map { card in
                var copy = card
                if !existingIDs.contains(card.id) { copy.id = "projected:\(card.id)" }
                return copy
            }
        }

        let defaults = store.defaults
        let followsToday = defaults?.object(forKey: FlutterPreferenceKeys.followToday) as? Bool ?? true
        let explicitDate = store.dashboardState()?["selectedDate"] as? String
        let selectedDate = selectedDateOverride ?? (followsToday ? now : explicitDate.flatMap { FlutterDate.parse($0) })
        let strings = DashboardStrings(
            noEvents: localized("noEvents"),
            hiddenContent: localized("hiddenContent"),
            checkInApp: localized("openAppToRefresh"),
            dDayToday: localized("today"),
            dPlusPrefix: "D+",
            timePassed: localized("timePassed", defaultValue: "Time passed"),
            hoursMinutesRemaining: localized("remaining", defaultValue: "left"),
            remainingTasks: localized("remaining", defaultValue: "Remaining")
        )
        let entitlement = Entitlement(cachedJSON: defaults?.string(forKey: FlutterPreferenceKeys.purchaseState))
        let isPro = entitlement.isPro && (entitlement.expirationDate.map { $0 > now } ?? true)
        let resolved = SmartLockScreenSchedule.resolve(
            cards: cards, settings: defaults.map(LockScreenSettings.load(from:)) ?? LockScreenSettings(),
            store: store, at: now, isPro: isPro
        )
        let snapshot = DashboardComposer(strings: strings).compose(
            cards: resolved.cards,
            selectedDate: resolved.ruleID == nil ? selectedDate : now,
            settings: resolved.settings,
            privacyMode: PrivacyMode(fromStored: defaults?.string(forKey: FlutterPreferenceKeys.defaultPrivacyMode)),
            now: now
        )
        return snapshot.dictionary(isPro: isPro)
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

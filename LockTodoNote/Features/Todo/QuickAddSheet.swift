import SwiftUI
import LockTodoNoteShared

/// Capture sheet for a todo or a memo. Multi-line by design — the Flutter
/// build let people paste several lines at once and that habit should survive.
struct QuickAddSheet: View {
    let mode: QuickAddMode
    var date: Date = Date()
    var source = "app"

    @EnvironmentObject private var cardStore: CardStore
    @EnvironmentObject private var settingsStore: LockScreenSettingsStore
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var text: String = ""
    @State private var selectsMemo: Bool?
    @State private var recurrence: TodoRecurrence = .none
    @State private var advancedRepeat: AdvancedRepeatRule?
    @State private var smartEnabled = true
    @State private var hasManualRecurrence = false
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    init(mode: QuickAddMode, date: Date = Date(), source: String = "app", initialRecurrence: TodoRecurrence = .none) {
        self.mode = mode
        self.date = date
        self.source = source
        _recurrence = State(initialValue: initialRecurrence)
        _hasManualRecurrence = State(initialValue: initialRecurrence != .none)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .focused($isFocused)
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("quickAdd.editor")
                }

                if mode == .memo {
                    Section {
                        Toggle(appString(localized: "memo.showOnLockScreen", defaultValue: "Show on Lock Screen"), isOn: Binding(
                            get: { selectsMemo ?? environment.newMemoReplacesDisplayedMemo },
                            set: { selectsMemo = $0 }
                        ))
                        .disabled(environment.newMemoIsExcludedByRule)
                        .accessibilityIdentifier("quickAdd.memo.showOnLockScreen")
                    } footer: {
                        Text(environment.newMemoIsExcludedByRule
                            ? bilingualString(korean: "현재 구성에는 선택한 메모만 표시돼요.", english: "This layout shows selected notes only.")
                            : bilingualString(korean: "표시할 메모만 교체하며 템플릿은 바꾸지 않습니다.", english: "This replaces the selected note without changing your template."))
                    }
                }

                if mode == .todo {
                    Section {
                        SmartQuickAddPreview(todos: smartTodos, isEnabled: $smartEnabled)
                    }
                    Section(appString(localized: "quickAdd.repeat", defaultValue: "Repeat")) {
                        if advancedRepeat == nil {
                            Picker(
                                appString(localized: "quickAdd.repeat", defaultValue: "Repeat"),
                                selection: Binding(
                                    get: { smartTodos.first?.recurrence ?? recurrence },
                                    set: { recurrence = $0; advancedRepeat = nil; hasManualRecurrence = true }
                                )
                            ) {
                                ForEach(TodoRecurrence.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        AdvancedRepeatPicker(rule: $advancedRepeat, startDate: smartTodos.first?.scheduledDate ?? date) {
                            recurrence = .none
                            hasManualRecurrence = true
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appString(localized: "common.cancel", defaultValue: "Cancel")) {
                        analytics.captureEnded(source: source, result: "cancelled")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appString(localized: "common.save", defaultValue: "Save")) { save() }
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("quickAdd.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            isFocused = true
            analytics.quickCaptureFocused(type: mode.rawValue, source: source)
        }
        .onDisappear { analytics.captureEnded(source: source, result: "interrupted") }
        .alert(
            saveError ?? "",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { saveError = nil }
        }
    }

    private var title: String {
        switch mode {
        case .todo: appString(localized: "home.addTodo", defaultValue: "Add todo")
        case .memo: appString(localized: "home.addMemo", defaultValue: "Add memo")
        }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var smartTodos: [SmartTodo] {
        SmartQuickAddParser.parse(
            text, defaultDate: date,
            recurrenceOverride: hasManualRecurrence ? recurrence : nil, enabled: smartEnabled
        )
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        switch mode {
        case .todo:
            let lines = QuickCaptureService.parseTodoLines(from: trimmed)
            guard cardStore.addTodos(
                texts: [trimmed], to: date, recurrence: recurrence, smartEnabled: smartEnabled,
                recurrenceOverride: hasManualRecurrence ? recurrence : nil, advancedRepeat: advancedRepeat
            ) else {
                failSave(operation: "create_todo")
                return
            }
            let todos = cardStore.todoCards(on: date).flatMap(\.checklistItems)
            analytics.todoCreated(
                taskCount: todos.count,
                remainingCount: todos.filter { !$0.isDone }.count,
                hasMemo: !cardStore.memoCards(on: date).isEmpty,
                templateId: settingsStore.settings.template.rawValue,
                source: source,
                createdCount: lines.count
            )
            if lines.count > 1 { analytics.multilineTodoImported(count: lines.count, source: source) }
        case .memo:
            guard cardStore.addMemo(text: trimmed, to: date,
                                    pinned: !environment.newMemoIsExcludedByRule &&
                                        (selectsMemo ?? environment.newMemoReplacesDisplayedMemo)) else {
                failSave(operation: "create_memo")
                return
            }
            analytics.memoCreated(source: source, templateId: settingsStore.settings.template.rawValue)
        }
        dismiss()
    }

    private func failSave(operation: String) {
        analytics.cardSaveFailed(operation: operation, source: source)
        saveError = appString(
            localized: "storage.writeFailed",
            defaultValue: "That change could not be saved. Your text is still here; please try again."
        )
    }
}

/// Editing an existing memo. Todos are edited inline in the list.
struct MemoEditorSheet: View {
    let card: Card

    @EnvironmentObject private var cardStore: CardStore
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var showOnLockScreen: Bool = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                }
                Section {
                    Toggle(
                        appString(localized: "memo.showOnLockScreen", defaultValue: "Show on Lock Screen"),
                        isOn: $showOnLockScreen
                    )
                } footer: {
                    Text(
                        appString(localized: "memo.showOnLockScreenFooter",
                            defaultValue: "Only one memo appears on the Lock Screen at a time."
                        )
                    )
                }
            }
            .navigationTitle(appString(localized: "memo.edit", defaultValue: "Edit memo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appString(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appString(localized: "common.save", defaultValue: "Save")) { save() }
                }
            }
        }
        .onAppear {
            text = card.body.isEmpty ? card.title : card.body
            showOnLockScreen = card.isPinned
        }
        .alert(
            saveError ?? "",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { saveError = nil }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if cardStore.delete(id: card.id) { dismiss() } else { failSave() }
            return
        }
        var updated = card
        updated.title = CardMutations.memoTitle(from: trimmed)
        updated.body = trimmed
        updated.isPinned = showOnLockScreen
        updated.showOnLockScreen = showOnLockScreen
        updated.updatedAt = Date()
        if cardStore.upsert(updated) { dismiss() } else { failSave() }
    }

    private func failSave() {
        analytics.cardSaveFailed(operation: "update_memo", source: "memo_editor")
        saveError = appString(
            localized: "storage.writeFailed",
            defaultValue: "That change could not be saved. Your text is still here; please try again."
        )
    }
}

extension TodoRecurrence {
    var displayName: String {
        switch self {
        case .none: appString(localized: "repeat.none", defaultValue: "Today only")
        case .daily: appString(localized: "repeat.daily", defaultValue: "Every day")
        case .weekdays: appString(localized: "repeat.weekdays", defaultValue: "Monday to Friday")
        case .weekly: appString(localized: "repeat.weekly", defaultValue: "Every week")
        }
    }
}

struct TodoEditorSheet: View {
    let entry: TodoEntry

    @EnvironmentObject private var cardStore: CardStore
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var recurrence: TodoRecurrence = .none
    @State private var advancedRepeat: AdvancedRepeatRule?
    @State private var saveError: String?
    @State private var deletingTodo: TodoEntry?

    var body: some View {
        NavigationStack {
            Form {
                TextField(appString(localized: "home.todos", defaultValue: "Todo"), text: $text)
                    .accessibilityIdentifier("todo.editor.text")
                if advancedRepeat == nil {
                    Picker(
                        appString(localized: "quickAdd.repeat", defaultValue: "Repeat"),
                        selection: Binding(get: { recurrence }, set: { recurrence = $0; advancedRepeat = nil })
                    ) {
                        ForEach(TodoRecurrence.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
                AdvancedRepeatPicker(rule: $advancedRepeat, startDate: entry.card.day()) {
                    recurrence = .none
                }
            }
            .navigationTitle(appString(localized: "common.edit", defaultValue: "Edit"))
            .modifier(TodoDeletionModifier(entry: $deletingTodo))
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    if AppleReminderMirror.reminderID(from: entry.card.id) == nil {
                        Button(appString(localized: "common.delete", defaultValue: "Delete"), role: .destructive) {
                            guard cardStore.materializeCalendarTodo(id: entry.card.id, on: entry.card.targetDateTime ?? entry.card.createdAt) else { return }
                            deletingTodo = entry
                        }.accessibilityIdentifier("todo.editor.delete")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(appString(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appString(localized: "common.save", defaultValue: "Save")) { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("todo.editor.save")
                }
            }
        }
        .onChange(of: cardStore.cards) { _ in
            if cardStore.card(id: entry.card.id)?.checklistItems.contains(where: { $0.id == entry.item.id }) != true { dismiss() }
        }
        .onAppear {
            text = entry.item.text
            recurrence = entry.item.recurrence
            advancedRepeat = entry.item.advancedRepeat
        }
        .alert(
            saveError ?? "",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button(appString(localized: "common.ok", defaultValue: "OK")) { saveError = nil }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let itemIndex = entry.card.checklistItems.firstIndex(where: { $0.id == entry.item.id }) else {
            dismiss()
            return
        }
        var card = entry.card
        card.checklistItems[itemIndex].text = trimmed
        if card.checklistItems[itemIndex].recurrence != recurrence || card.checklistItems[itemIndex].advancedRepeat != advancedRepeat {
            card.checklistItems[itemIndex].recurrenceAnchorDate = card.targetDateTime ?? card.createdAt
        }
        card.checklistItems[itemIndex].advancedRepeat = advancedRepeat
        card.checklistItems[itemIndex].recurrence = recurrence
        if itemIndex == 0 { card.title = trimmed }
        card.updatedAt = Date()
        guard cardStore.upsert(card) else {
            analytics.cardSaveFailed(operation: "update_todo", source: "todo_editor")
            saveError = appString(
                localized: "storage.writeFailed",
                defaultValue: "That change could not be saved. Please try again."
            )
            return
        }
        dismiss()
    }
}

/// Shared by Today and the calendar editor so every delete has identical semantics.
struct TodoDeletionModifier: ViewModifier {
    @Binding var entry: TodoEntry?
    @EnvironmentObject private var cardStore: CardStore
    @State private var confirmSeries = false
    @State private var showScope = false
    @State private var failed = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                bilingualString(korean: "반복 할 일 삭제 범위", english: "Delete repeating task"),
                isPresented: $showScope,
                titleVisibility: .visible
            ) {
                Button(bilingualString(korean: "이 날짜만 삭제", english: "Delete this day only"), role: .destructive) { remove(.occurrence) }
                Button(bilingualString(korean: "앞으로 반복 중단", english: "Stop future repeats"), role: .destructive) { remove(.future) }
                Button(bilingualString(korean: "전체 반복 삭제…", english: "Delete entire series…"), role: .destructive) { confirmSeries = true }
                Button(appString(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) { entry = nil }
            }
            .alert(bilingualString(korean: "전체 반복을 삭제할까요?", english: "Delete entire series?"), isPresented: $confirmSeries) {
                Button(appString(localized: "common.delete", defaultValue: "Delete"), role: .destructive) { remove(.series) }
                Button(appString(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) { entry = nil }
            } message: {
                Text(bilingualString(korean: "이전 완료 기록을 포함한 모든 반복 항목이 삭제됩니다.", english: "All occurrences, including past completion history, will be deleted."))
            }
            .alert(bilingualString(korean: "삭제를 저장하지 못했습니다. 다시 시도해 주세요.", english: "Could not save the deletion. Please try again."), isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
            .onChange(of: entry?.compositeId) { _ in
                if entry?.item.hasRecurrence == false { remove(.occurrence) }
                else if entry != nil { showScope = true }
            }
    }

    private func remove(_ scope: CardMutations.TodoDeletionScope) {
        guard let value = entry else { return }
        failed = !cardStore.deleteTodo(cardID: value.card.id, itemID: value.item.id,
                                      on: value.card.targetDateTime ?? value.card.createdAt, scope: scope)
        entry = nil
    }
}

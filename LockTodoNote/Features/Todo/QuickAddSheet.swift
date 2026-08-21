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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var text: String = ""
    @State private var recurrence: TodoRecurrence = .none
    @FocusState private var isFocused: Bool

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

                if mode == .todo {
                    Section(appString(localized: "quickAdd.repeat", defaultValue: "Repeat")) {
                        Picker(
                            appString(localized: "quickAdd.repeat", defaultValue: "Repeat"),
                            selection: $recurrence
                        ) {
                            ForEach(TodoRecurrence.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appString(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appString(localized: "common.save", defaultValue: "Save")) { save() }
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("quickAdd.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
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

    private func save() {
        guard !trimmed.isEmpty else { return }
        switch mode {
        case .todo:
            let lines = trimmed
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            cardStore.addTodos(texts: lines, to: date, recurrence: recurrence)
            let todos = cardStore.todoCards(on: date).flatMap(\.checklistItems)
            analytics.todoCreated(
                taskCount: todos.count,
                remainingCount: todos.filter { !$0.isDone }.count,
                hasMemo: !cardStore.memoCards(on: date).isEmpty,
                templateId: settingsStore.settings.template.rawValue,
                source: source
            )
            if lines.count > 1 { analytics.multilineTodoImported(count: lines.count) }
        case .memo:
            cardStore.addMemo(text: trimmed, to: date)
            analytics.memoCreated(source: source)
        }
        dismiss()
    }
}

/// Editing an existing memo. Todos are edited inline in the list.
struct MemoEditorSheet: View {
    let card: Card

    @EnvironmentObject private var cardStore: CardStore
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var showOnLockScreen: Bool = false

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
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cardStore.delete(id: card.id)
            dismiss()
            return
        }
        var updated = card
        updated.title = CardMutations.memoTitle(from: trimmed)
        updated.body = trimmed
        updated.isPinned = showOnLockScreen
        updated.showOnLockScreen = showOnLockScreen
        updated.updatedAt = Date()
        cardStore.upsert(updated)
        dismiss()
    }
}

extension TodoRecurrence {
    var displayName: String {
        switch self {
        case .none: appString(localized: "repeat.none", defaultValue: "Never")
        case .daily: appString(localized: "repeat.daily", defaultValue: "Every day")
        case .weekdays: appString(localized: "repeat.weekdays", defaultValue: "Weekdays")
        case .weekly: appString(localized: "repeat.weekly", defaultValue: "Every week")
        }
    }
}

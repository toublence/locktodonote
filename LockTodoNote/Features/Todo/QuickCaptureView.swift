import SwiftUI
import LockTodoNoteShared

/// Compact, reusable capture used by Today and Calendar.
struct QuickCaptureView: View {
    let date: Date
    let source: String
    var allowedModes: [QuickAddMode] = [.todo, .memo]
    var onSaved: ((QuickAddMode, Int) -> Void)?

    @EnvironmentObject private var cardStore: CardStore
    @EnvironmentObject private var settingsStore: LockScreenSettingsStore
    @EnvironmentObject private var dashboard: DashboardCoordinator
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    @State private var mode: QuickAddMode = .todo
    @State private var text = ""
    @State private var confirmation: String?
    @State private var recurrence: TodoRecurrence = .none
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if allowedModes.count > 1 {
                Picker(
                    appString(localized: "capture.type", defaultValue: "Capture type"),
                    selection: $mode
                ) {
                    Text(appString(localized: "home.todos", defaultValue: "Todo"))
                        .tag(QuickAddMode.todo)
                    Text(appString(localized: "home.memos", defaultValue: "Memo"))
                        .tag(QuickAddMode.memo)
                }
                .pickerStyle(.segmented)
            }

            if mode == .todo {
                HStack {
                    Text(appString(localized: "quickAdd.repeat", defaultValue: "Show this todo"))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Picker("", selection: $recurrence) {
                        ForEach(TodoRecurrence.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    appString(localized: "capture.prompt", defaultValue: "What would you like to add?"),
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(isFocused ? 2...7 : 1...2)
                .frame(minHeight: isFocused ? 140 : 48, alignment: .topLeading)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("quickCapture.\(source)")

                Button(action: save) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(palette.accent, in: Circle())
                        .foregroundStyle(palette.onPrimary)
                }
                .buttonStyle(.plain)
                .disabled(trimmedText.isEmpty)
                .opacity(trimmedText.isEmpty ? 0.45 : 1)
                .accessibilityLabel(appString(localized: "common.save", defaultValue: "Save"))
            }
            .padding(12)
            .background(palette.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isFocused)

            if let confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(palette.success)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .onAppear {
            if !allowedModes.contains(mode) { mode = allowedModes.first ?? .memo }
            settingsStore.settings.selectedContentSection = mode == .todo ? .todo : .memo
            dashboard.publish()
        }
        .onChange(of: mode) { newMode in
            settingsStore.settings.selectedContentSection = newMode == .todo ? .todo : .memo
            dashboard.publish()
        }
        .onChange(of: isFocused) { focused in
            if focused { analytics.quickCaptureFocused(type: mode.rawValue, source: source) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(appString(localized: "common.done", defaultValue: "Done")) {
                    if !trimmedText.isEmpty { save() }
                    isFocused = false
                }
            }
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

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedText.isEmpty else { return }

        switch mode {
        case .todo:
            let lines = trimmedText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return }
            guard cardStore.addTodos(texts: lines, to: date, recurrence: recurrence) else {
                recordSaveFailure(operation: "create_todo")
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
            confirmation = String(
                format: appString(localized: "capture.todosAdded", defaultValue: "%d todos added"),
                lines.count
            )
            onSaved?(.todo, lines.count)

        case .memo:
            guard cardStore.addMemo(text: trimmedText, to: date) else {
                recordSaveFailure(operation: "create_memo")
                return
            }
            analytics.memoCreated(source: source, templateId: settingsStore.settings.template.rawValue)
            confirmation = appString(localized: "capture.memoAdded", defaultValue: "Memo added")
            onSaved?(.memo, 1)
        }

        text = ""
        dashboard.publish()
    }

    private func recordSaveFailure(operation: String) {
        analytics.cardSaveFailed(operation: operation, source: source)
        saveError = appString(
            localized: "storage.writeFailed",
            defaultValue: "That change could not be saved. Your text is still here; please try again."
        )
    }
}

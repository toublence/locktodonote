import LockTodoNoteShared
import SwiftUI

struct SmartQuickAddPreview: View {
    let todos: [SmartTodo]
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                bilingualString(korean: "문장 자동 인식", english: "Smart Quick Add"),
                isOn: $isEnabled
            )
            .font(.caption)
            if isEnabled {
                ForEach(Array(todos.indices.prefix(3)), id: \.self) { index in
                    let todo = todos[index]
                    if todo.recognized {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(todo.text).font(.caption.weight(.semibold))
                                Text(summary(todo)).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    }
                }
                if todos.allSatisfy({ !$0.recognized }) {
                    Text(bilingualString(
                        korean: "예: 내일 오후 3시 병원 예약 · 매주 월요일 운동",
                        english: "Try: tomorrow 3pm appointment · every Monday exercise"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func summary(_ todo: SmartTodo) -> String {
        let date = appDateString(
            todo.scheduledDate, dateStyle: .medium,
            timeStyle: todo.hasDueTime ? .short : .none
        )
        return todo.recurrence == .none ? date : "\(date) · \(todo.recurrence.displayName)"
    }
}

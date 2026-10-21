import Foundation
import Testing
@testable import LockTodoNoteShared

@Suite("Shared queue transactions")
struct AppGroupQueueTests {
    @Test func concurrentCapturesAndAcknowledgementsKeepNewItems() {
        let suite = "test.queues.\(UUID().uuidString)"
        let store = AppGroupStore(suiteName: suite)
        defer { store.defaults?.removePersistentDomain(forName: suite) }
        DispatchQueue.concurrentPerform(iterations: 24) { index in
            store.appendPendingQuickAdd(PendingQuickAdd(
                id: "\(index)", text: "할 일 🌱 \(index)", target: .todo,
                dateKey: "2026-10-21", createdAt: Date()
            ))
        }
        #expect(store.pendingQuickAdds().count == 24)
        let acknowledged = Set(store.pendingQuickAdds().map(\.id))
        store.appendPendingQuickAdd(PendingQuickAdd(
            id: "new", text: "New item", target: .todo,
            dateKey: "2026-10-21", createdAt: Date()
        ))
        store.acknowledgePendingQuickAdds(ids: acknowledged)
        #expect(store.pendingQuickAdds().map(\.id) == ["new"])
    }

    @Test func completionDeduplicationSurvivesConcurrentWriters() {
        let suite = "test.queues.\(UUID().uuidString)"
        let store = AppGroupStore(suiteName: suite)
        defer { store.defaults?.removePersistentDomain(forName: suite) }
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            store.appendPendingCompletedTodo(PendingCompletedTodo(
                id: "card:item", completedAt: Date(), source: "widget"
            ))
        }
        let completions = store.pendingCompletedTodos()
        #expect(completions.count == 1)
        store.acknowledgePendingCompletedTodos(eventIds: Set(completions.map(\.eventId)))
        #expect(store.pendingCompletedTodos().isEmpty)
    }
}

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


@Suite("Widget publication budget")
struct WidgetPublicationTests {
    private func equal(_ left: [String: Any], _ right: [String: Any]) -> Bool {
        NSDictionary(dictionary: left).isEqual(to: right)
    }

    @Test func clockOnlyRepublicationDoesNotInvalidateWidgets() {
        let first = AppGroupStore.widgetReloadSignature(payload: ["updatedAt": 1, "todoItems": ["Walk my dog"]], context: [:])
        let later = AppGroupStore.widgetReloadSignature(payload: ["updatedAt": 2, "todoItems": ["Walk my dog"]], context: [:])
        #expect(equal(first, later))
    }

    @Test func deletionInvalidatesEvenWhenTheInjectedClockIsUnchanged() {
        let first = AppGroupStore.widgetReloadSignature(payload: ["updatedAt": 1, "todoItems": ["Walk my dog", "Keep this task"]], context: [:])
        let deleted = AppGroupStore.widgetReloadSignature(payload: ["updatedAt": 1, "todoItems": ["Keep this task"]], context: [:])
        #expect(!equal(first, deleted))
    }

    @Test func deferredRefreshCanRetryAfterTheCoalescingWindow() {
        let state = AppGroupStore.widgetReloadSignature(payload: ["todoItems": ["Keep this task"]], context: [:])
        #expect(!AppGroupStore.shouldReloadWidget(signature: state, previous: state, lastRequest: 100, now: 129))
        #expect(AppGroupStore.shouldReloadWidget(signature: state, previous: state, lastRequest: 100, now: 130))
        let changed = AppGroupStore.widgetReloadSignature(payload: ["todoItems": [String]()], context: [:])
        #expect(AppGroupStore.shouldReloadWidget(signature: changed, previous: state, lastRequest: 100, now: 101))
    }

    @Test func modeAndFutureSourceChangesInvalidateIdenticalVisibleContent() {
        let payload: [String: Any] = ["selectedDate": "2026-10-28", "todoItems": [String]()]
        let first = AppGroupStore.widgetReloadSignature(payload: payload, context: ["followToday": true, "revision": 1])
        let pinned = AppGroupStore.widgetReloadSignature(payload: payload, context: ["followToday": false, "revision": 1])
        let futureEdit = AppGroupStore.widgetReloadSignature(payload: payload, context: ["followToday": true, "revision": 2])
        #expect(!equal(first, pinned))
        #expect(!equal(first, futureEdit))
    }
}

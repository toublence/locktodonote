import Foundation
import LockTodoNoteShared

/// Reads and writes the card file in the App Group container.
///
/// Loading is not a pure read: it drains the queues extensions filled while the
/// app was closed and applies the same four transformations the Flutter
/// repository ran on every load, in the same order.
struct CardRepository {
    let store: AppGroupStore
    private let calendar: Calendar

    init(store: AppGroupStore = AppGroupStore(), calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    struct LoadResult {
        var cards: [Card]
        /// Completions and captures that arrived while the app was closed —
        /// the caller forwards these to analytics.
        var mergedCompletions: [PendingCompletedTodo]
        var mergedQuickAdds: [PendingQuickAdd]
    }

    func load(now: Date = Date()) throws -> LoadResult {
        var cards = try readFile()
        var didChange = false

        let quickAdds = store.pendingQuickAdds()
        let quickAddResult = CardMutations.applyQuickAdds(quickAdds, to: cards, calendar: calendar)
        cards = quickAddResult.cards
        didChange = didChange || quickAddResult.didChange

        // A Shortcut item can be added and completed before the app next
        // opens. Merge additions first so its completion can resolve in the
        // same durable commit.
        let completions = store.pendingCompletedTodos()
        let completionResult = CardMutations.applyCompletions(
            completions, to: cards, calendar: calendar, now: now
        )
        cards = completionResult.cards
        didChange = didChange || completionResult.didChange

        let rollover = CardMutations.rollOverIncompleteTodos(cards, calendar: calendar, now: now)
        cards = rollover.cards
        didChange = didChange || rollover.didChange

        let recurring = CardMutations.createRecurringTodosForToday(cards, calendar: calendar, now: now)
        cards = recurring.cards
        didChange = didChange || recurring.didChange

        cards = CardMutations.sorted(cards)
        if didChange {
            try write(cards)
        }
        // New items appended while writing remain because acknowledgement is ID based.
        store.acknowledgePendingCompletedTodos(eventIds: Set(completions.map(\.eventId)))
        store.acknowledgePendingQuickAdds(ids: Set(quickAdds.map(\.id)))
        return LoadResult(
            cards: cards,
            mergedCompletions: completions,
            mergedQuickAdds: quickAdds
        )
    }

    func save(_ cards: [Card]) throws {
        try write(CardMutations.sorted(cards))
    }

    // MARK: - File access

    private func readFile() throws -> [Card] {
        guard let url = store.cardStoreURL, FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([Card].self, from: data)
    }

    private func write(_ cards: [Card]) throws {
        guard let url = store.cardStoreURL else { throw CardRepositoryError.noContainer }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(cards).write(to: url, options: .atomic)
        store.relaxFileProtection(at: url)
    }

    enum CardRepositoryError: Error {
        case noContainer
    }
}

import Foundation

/// The four transformations the Flutter build ran every single time cards were
/// loaded. They are the app's real business rules, so they are modelled here as
/// pure functions that can be tested against the old behaviour.
///
/// Order matters and matches `LocalCardRepository.loadCards()`:
/// merge completions → merge quick adds → roll over → create recurrences.
public enum CardMutations {
    // MARK: - 1. Completions captured while the app was closed

    /// Applies Lock Screen / Dynamic Island completions to their items.
    /// Ids arrive as the composite `cardId:itemId`.
    public static func applyCompletions(
        _ completions: [PendingCompletedTodo],
        to cards: [Card],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> (cards: [Card], didChange: Bool) {
        guard !completions.isEmpty else { return (cards, false) }
        let byId = Dictionary(completions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var didChange = false

        let updated = cards.map { card -> Card in
            guard !card.checklistItems.isEmpty else { return card }
            var cardChanged = false
            let items = card.checklistItems.map { item -> ChecklistItem in
                guard
                    !item.isDone,
                    let completion = byId["\(card.id):\(item.id)"]
                else { return item }
                cardChanged = true
                return item.markingDone(
                    at: completion.completedAt,
                    source: completion.source,
                    calendar: calendar
                )
            }
            guard cardChanged else { return card }
            didChange = true
            var copy = card
            copy.checklistItems = items
            copy.updatedAt = now
            return copy
        }
        return (updated, didChange)
    }

    // MARK: - 2. Shortcut captures

    /// Turns queued Shortcuts text into cards.
    ///
    /// Unlike the Flutter build this does not re-check the free daily limit.
    /// The intent already counted the add against the shared App Group counter
    /// before enqueueing; re-checking here used a *second*, standard-defaults
    /// counter, so the two could disagree and silently drop a captured item.
    public static func applyQuickAdds(
        _ quickAdds: [PendingQuickAdd],
        to cards: [Card],
        calendar: Calendar = .current
    ) -> (cards: [Card], didChange: Bool) {
        guard !quickAdds.isEmpty else { return (cards, false) }
        var result = cards
        var existingIds = Set(cards.map(\.id))
        var didChange = false

        for quickAdd in quickAdds {
            guard !existingIds.contains(quickAdd.id) else { continue }
            let day = FlutterDate.date(fromKey: quickAdd.dateKey, calendar: calendar) ?? quickAdd.createdAt
            let target = combine(day: day, time: quickAdd.createdAt, calendar: calendar)

            switch quickAdd.target {
            case .memo:
                // Only one memo is pinned to the Lock Screen at a time.
                for index in result.indices where result[index].type == .quickNote && result[index].isPinned {
                    result[index].isPinned = false
                    result[index].showOnLockScreen = false
                }
                result.append(
                    Card(
                        id: quickAdd.id,
                        title: memoTitle(from: quickAdd.text),
                        body: quickAdd.text,
                        type: .quickNote,
                        privacyMode: .full,
                        isPinned: true,
                        showOnLockScreen: true,
                        targetDateTime: target,
                        createdAt: quickAdd.createdAt,
                        updatedAt: quickAdd.createdAt
                    )
                )
            case .todo:
                result.append(
                    Card(
                        id: quickAdd.id,
                        title: quickAdd.text,
                        type: .checklist,
                        privacyMode: .full,
                        checklistItems: [
                            ChecklistItem(id: "\(quickAdd.id)-item-0", text: quickAdd.text)
                        ],
                        showOnLockScreen: true,
                        targetDateTime: target,
                        createdAt: quickAdd.createdAt,
                        updatedAt: quickAdd.createdAt
                    )
                )
            }
            existingIds.insert(quickAdd.id)
            didChange = true
        }
        return (result, didChange)
    }

    // MARK: - 3. Roll over unfinished work

    /// Moves yesterday's unfinished todos onto today so nothing is stranded in
    /// the past. A card that also holds completed items is split: the original
    /// keeps its history, a new card carries the leftovers forward.
    public static func rollOverIncompleteTodos(
        _ cards: [Card],
        calendar: Calendar = .current,
        now: Date = Date(),
        idFactory: (Int) -> String = { "\(Int(Date().timeIntervalSince1970 * 1_000_000))-rollover-\($0)" }
    ) -> (cards: [Card], didChange: Bool) {
        let today = calendar.startOfDay(for: now)
        var result: [Card] = []
        result.reserveCapacity(cards.count)
        var didChange = false
        var rolloverIndex = 0

        for card in cards {
            let cardDay = card.day(calendar: calendar)
            guard card.type == .checklist, cardDay < today else {
                result.append(card)
                continue
            }
            let incomplete = card.checklistItems.filter { !$0.isDone }
            guard !incomplete.isEmpty else {
                result.append(card)
                continue
            }

            didChange = true
            let completed = card.checklistItems.filter(\.isDone)
            if completed.isEmpty {
                var moved = card
                moved.targetDateTime = today
                moved.updatedAt = now
                result.append(moved)
                continue
            }

            var history = card
            history.checklistItems = completed
            history.updatedAt = now
            result.append(history)

            var carried = card
            carried.id = idFactory(rolloverIndex)
            rolloverIndex += 1
            carried.title = incomplete[0].text
            carried.checklistItems = incomplete
            carried.targetDateTime = today
            carried.createdAt = now
            carried.updatedAt = now
            carried.lastActivatedAt = nil
            result.append(carried)
        }
        return (result, didChange)
    }

    // MARK: - 4. Recurring todos

    /// Creates today's occurrence for any repeating todo that does not have one.
    public static func createRecurringTodosForToday(
        _ cards: [Card],
        calendar: Calendar = .current,
        now: Date = Date(),
        idFactory: (Int) -> String = { "\(Int(Date().timeIntervalSince1970 * 1_000_000))-repeat-\($0)" }
    ) -> (cards: [Card], didChange: Bool) {
        let today = calendar.startOfDay(for: now)

        var series: [String: [(card: Card, item: ChecklistItem)]] = [:]
        for card in cards where card.type == .checklist {
            for item in card.checklistItems where item.recurrence != .none {
                series[item.effectiveRecurrenceId, default: []].append((card, item))
            }
        }
        guard !series.isEmpty else { return (cards, false) }

        var newCards: [Card] = []
        // Dictionary order is not stable, and the generated ids are sequential.
        // Sorting keeps a given library producing identical ids run to run.
        for key in series.keys.sorted() {
            guard var occurrences = series[key], !occurrences.isEmpty else { continue }
            let alreadyToday = occurrences.contains { $0.card.day(calendar: calendar) == today }
            if alreadyToday { continue }

            occurrences.sort { $0.card.day(calendar: calendar) < $1.card.day(calendar: calendar) }
            let seed = occurrences[0]
            let seedDay = seed.card.day(calendar: calendar)
            guard seed.item.recurrence.isDue(seedDate: seedDay, on: today, calendar: calendar) else { continue }

            let occurrenceId = idFactory(newCards.count)
            var occurrence = seed.card
            occurrence.id = occurrenceId
            occurrence.title = seed.item.text
            var item = seed.item.clearingCompletion()
            item.id = "\(occurrenceId)-item-0"
            item.recurrenceId = key
            occurrence.checklistItems = [item]
            occurrence.targetDateTime = today
            occurrence.createdAt = now
            occurrence.updatedAt = now
            occurrence.lastActivatedAt = nil
            newCards.append(occurrence)
        }

        guard !newCards.isEmpty else { return (cards, false) }
        return (cards + newCards, true)
    }

    // MARK: - Helpers

    /// First non-empty line, capped at 20 characters — the Flutter memo title rule.
    public static func memoTitle(from text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? text
        return String(firstLine.prefix(20))
    }

    /// Keeps the capture's time-of-day while placing it on the chosen day.
    public static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let clock = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: time)
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = clock.second
        components.nanosecond = clock.nanosecond
        return calendar.date(from: components) ?? day
    }

    /// Newest first — the order the Flutter repository persisted and the UI expects.
    public static func sorted(_ cards: [Card]) -> [Card] {
        cards.sorted { $0.updatedAt > $1.updatedAt }
    }
}

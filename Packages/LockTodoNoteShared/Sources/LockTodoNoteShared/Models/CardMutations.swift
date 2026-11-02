import Foundation

/// The four transformations the Flutter build ran every single time cards were
/// loaded. They are the app's real business rules, so they are modelled here as
/// pure functions that can be tested against the old behaviour.
///
/// Order matters and matches `LocalCardRepository.loadCards()`:
/// merge completions → merge quick adds → roll over → create recurrences.
public enum CardMutations {
    public enum TodoDeletionScope: Sendable { case occurrence, future, series }

    /// Delete a line, never its sibling lines. Retained rules preserve the anchor
    /// and exclusions even when the only occurrence is removed.
    public static func deleteTodo(
        _ cards: [Card], cardID: String, itemID: String, on date: Date,
        scope: TodoDeletionScope, calendar: Calendar = .current
    ) -> [Card] {
        guard AppleReminderMirror.reminderID(from: cardID) == nil,
              let source = cards.first(where: { $0.id == cardID }),
              let item = source.checklistItems.first(where: { $0.id == itemID }) else { return cards }
        let seriesID = item.effectiveRecurrenceId
        let key = FlutterDate.dateKey(date, calendar: calendar)
        var result = cards
        var affectedIDs: Set<String> = []
        if item.hasRecurrence, scope != .series {
            var rule = item
            rule.recurrenceAnchorDate = item.recurrenceAnchorDate ?? source.day(calendar: calendar)
            result[result.firstIndex(where: { $0.id == cardID })!].recurrenceRules.append(rule)
        }
        for index in result.indices {
            guard AppleReminderMirror.reminderID(from: result[index].id) == nil else { continue }
            func matching(_ value: ChecklistItem) -> Bool { value.effectiveRecurrenceId == seriesID }
            guard (result[index].checklistItems + result[index].recurrenceRules).contains(where: matching) else { continue }
            affectedIDs.insert(result[index].id)
            let previousFirstID = result[index].checklistItems.first?.id
            let dayKey = result[index].dayKey(calendar: calendar)
            func policy(_ value: ChecklistItem) -> ChecklistItem {
                guard matching(value), item.hasRecurrence else { return value }
                var value = value
                if scope == .occurrence { value.excludedDateKeys.insert(key) }
                if scope == .future { value.recurrenceEndDateKey = min(value.recurrenceEndDateKey ?? key, key) }
                return value
            }
            result[index].checklistItems = result[index].checklistItems.filter { value in
                guard matching(value) else { return true }
                if !item.hasRecurrence { return false }
                switch scope {
                case .occurrence: return dayKey != key
                case .future: return dayKey < key
                case .series: return false
                }
            }.map(policy)
            result[index].recurrenceRules = result[index].recurrenceRules.filter {
                !(scope == .series && matching($0))
            }.map(policy)
            if let first = result[index].checklistItems.first, first.id != previousFirstID { result[index].title = first.text }
        }
        return result.filter { !affectedIDs.contains($0.id) || $0.type != .checklist || !$0.checklistItems.isEmpty || !$0.recurrenceRules.isEmpty }
    }

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
            let day = FlutterDate.date(fromKey: quickAdd.dateKey, calendar: calendar) ?? quickAdd.createdAt
            let target = combine(day: day, time: quickAdd.createdAt, calendar: calendar)

            switch quickAdd.target {
            case .memo:
                guard !existingIds.contains(quickAdd.id) else { continue }
                // Only one memo is pinned to the Lock Screen at a time.
                for index in result.indices where result[index].type == .quickNote && result[index].isPinned {
                    result[index].isPinned = false
                    result[index].showOnLockScreen = false
                }
                let memoBody = QuickCaptureService.cleanMemoText(from: quickAdd.text)
                guard !memoBody.isEmpty else { continue }
                result.append(
                    Card(
                        id: quickAdd.id,
                        title: memoTitle(from: memoBody),
                        body: memoBody,
                        type: .quickNote,
                        privacyMode: .full,
                        isPinned: true,
                        showOnLockScreen: true,
                        targetDateTime: target,
                        createdAt: quickAdd.createdAt,
                        updatedAt: quickAdd.createdAt
                    )
                )
                existingIds.insert(quickAdd.id)
                didChange = true

            case .todo:
                if let todos = quickAdd.smartTodos {
                    for (index, todo) in todos.enumerated() {
                        let cardID = todos.count == 1 ? quickAdd.id : "\(quickAdd.id)-\(index)"
                        guard existingIds.insert(cardID).inserted else { continue }
                        result.append(todo.card(id: cardID, createdAt: quickAdd.createdAt))
                        didChange = true
                    }
                    continue
                }
                let lines = QuickCaptureService.parseTodoLines(from: quickAdd.text)
                guard !lines.isEmpty else { continue }
                if lines.count == 1 {
                    guard !existingIds.contains(quickAdd.id) else { continue }
                    let line = lines[0]
                    result.append(
                        Card(
                            id: quickAdd.id,
                            title: line,
                            type: .checklist,
                            privacyMode: .full,
                            checklistItems: [
                                ChecklistItem(id: "\(quickAdd.id)-item-0", text: line)
                            ],
                            showOnLockScreen: true,
                            targetDateTime: target,
                            createdAt: quickAdd.createdAt,
                            updatedAt: quickAdd.createdAt
                        )
                    )
                    existingIds.insert(quickAdd.id)
                    didChange = true
                } else {
                    for (index, line) in lines.enumerated() {
                        let cardId = "\(quickAdd.id)-\(index)"
                        guard !existingIds.contains(cardId) else { continue }
                        result.append(
                            Card(
                                id: cardId,
                                title: line,
                                type: .checklist,
                                privacyMode: .full,
                                checklistItems: [
                                    ChecklistItem(id: "\(cardId)-item-0", text: line)
                                ],
                                showOnLockScreen: true,
                                targetDateTime: target,
                                createdAt: quickAdd.createdAt,
                                updatedAt: quickAdd.createdAt
                            )
                        )
                        existingIds.insert(cardId)
                        didChange = true
                    }
                }
            }
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

        let policies = cards.flatMap { $0.checklistItems + $0.recurrenceRules }
            .filter(\.hasRecurrence)
        for original in cards {
            var card = original
            let targetKey = FlutterDate.dateKey(max(today, card.day(calendar: calendar)), calendar: calendar)
            card.checklistItems.removeAll { item in
                guard !item.isDone, item.hasRecurrence else { return false }
                let key = targetKey
                return policies.contains { policy in
                    policy.effectiveRecurrenceId == item.effectiveRecurrenceId &&
                    (policy.excludedDateKeys.contains(key) || policy.recurrenceEndDateKey.map { key >= $0 } == true)
                }
            }
            if card.checklistItems != original.checklistItems { didChange = true }
            // Preserve the original recurrence anchor before moving a legacy seed.
            for index in card.checklistItems.indices where card.day(calendar: calendar) < today && !card.checklistItems[index].isDone && card.checklistItems[index].hasRecurrence && card.checklistItems[index].recurrenceAnchorDate == nil {
                card.checklistItems[index].recurrenceAnchorDate = original.day(calendar: calendar)
            }
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

    /// Read-only calendar projection. Materialize an occurrence only when edited
    /// or completed, so browsing months does not create unbounded stored cards.
    public static func calendarTodos(
        _ cards: [Card], on date: Date, calendar: Calendar = .current, now: Date = Date()
    ) -> [Card] {
        let day = calendar.startOfDay(for: date)
        let stored = cards.filter { $0.type == .checklist && $0.day(calendar: calendar) == day }
        guard day > calendar.startOfDay(for: now) else { return stored }
        // Apple owns its recurrence; imported reminders must never be synthesized.
        let local = cards.filter { AppleReminderMirror.reminderID(from: $0.id) == nil }
        let existingIDs = Set(local.map(\.id))
        let projected = createRecurringTodosForToday(local, calendar: calendar, now: day).cards
            .filter { !existingIDs.contains($0.id) }
            .map { card -> Card in
                var copy = card
                let seriesID = card.checklistItems[0].effectiveRecurrenceId
                let encoded = Data(seriesID.utf8).base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                copy.id = "calendar-repeat-\(FlutterDate.dateKey(day, calendar: calendar))-\(encoded)"
                copy.checklistItems[0].id = "\(copy.id)-item-0"
                return copy
            }
        return stored + projected
    }

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
            for item in card.checklistItems + card.recurrenceRules where item.hasRecurrence {
                series[item.effectiveRecurrenceId, default: []].append((card, item))
            }
        }
        guard !series.isEmpty else { return (cards, false) }

        var newCards: [Card] = []
        // Dictionary order is not stable, and the generated ids are sequential.
        // Sorting keeps a given library producing identical ids run to run.
        for key in series.keys.sorted() {
            guard var occurrences = series[key], !occurrences.isEmpty else { continue }
            let alreadyToday = cards.contains { card in
                card.day(calendar: calendar) == today && card.checklistItems.contains {
                    $0.hasRecurrence && $0.effectiveRecurrenceId == key
                }
            }
            if alreadyToday { continue }

            occurrences.sort { $0.card.day(calendar: calendar) < $1.card.day(calendar: calendar) }
            var seed = occurrences[0]
            // Merge durable policies from all copies; an old source cannot revive
            // a stopped series even if it is the earliest recurrence seed.
            seed.item.excludedDateKeys = occurrences.reduce(into: Set<String>()) { $0.formUnion($1.item.excludedDateKeys) }
            seed.item.recurrenceEndDateKey = occurrences.compactMap { $0.item.recurrenceEndDateKey }.min()
            let seedDay = seed.item.recurrenceAnchorDate ?? seed.card.day(calendar: calendar)
            guard seed.item.isRecurrenceDue(seedDate: seedDay, on: today, calendar: calendar) else { continue }

            let occurrenceId = idFactory(newCards.count)
            var occurrence = seed.card
            occurrence.id = occurrenceId
            occurrence.title = seed.item.text
            var item = seed.item.clearingCompletion()
            item.id = "\(occurrenceId)-item-0"
            item.recurrenceId = key
            if let dueDate = item.dueDate {
                item.dueDate = combine(day: today, time: dueDate, calendar: calendar)
            }
            occurrence.checklistItems = [item]
            occurrence.recurrenceRules = []
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

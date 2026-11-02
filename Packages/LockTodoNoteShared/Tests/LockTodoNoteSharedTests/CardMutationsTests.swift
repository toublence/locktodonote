import Foundation
import Testing

@testable import LockTodoNoteShared

@Suite("Card load-time mutations")
struct CardMutationsTests {
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func day(_ key: String) -> Date {
        FlutterDate.date(fromKey: key, calendar: calendar)!
    }

    private func todoCard(
        id: String,
        day dayKey: String,
        items: [ChecklistItem],
        type: CardType = .checklist
    ) -> Card {
        let date = day(dayKey)
        return Card(
            id: id,
            title: items.first?.text ?? "",
            type: type,
            checklistItems: items,
            targetDateTime: date,
            createdAt: date,
            updatedAt: date
        )
    }

    // MARK: - Completions

    @Test func appliesCompletionByCompositeId() {
        let card = todoCard(id: "c1", day: "2026-08-21", items: [
            ChecklistItem(id: "i1", text: "Milk"),
            ChecklistItem(id: "i2", text: "Eggs"),
        ])
        let completedAt = day("2026-08-21").addingTimeInterval(3600 * 10)
        let (result, didChange) = CardMutations.applyCompletions(
            [PendingCompletedTodo(id: "c1:i2", completedAt: completedAt, source: "live_activity")],
            to: [card],
            calendar: calendar
        )

        #expect(didChange)
        #expect(!result[0].checklistItems[0].isDone)
        #expect(result[0].checklistItems[1].isDone)
        #expect(result[0].checklistItems[1].completedSource == "live_activity")
        #expect(result[0].checklistItems[1].completedDateKey == "2026-08-21")
    }

    @Test func ignoresCompletionForUnknownOrAlreadyDoneItems() {
        let card = todoCard(id: "c1", day: "2026-08-21", items: [
            ChecklistItem(id: "i1", text: "Milk", isDone: true)
        ])
        let (result, didChange) = CardMutations.applyCompletions(
            [
                PendingCompletedTodo(id: "c1:i1", completedAt: Date(), source: "live_activity"),
                PendingCompletedTodo(id: "nope:nope", completedAt: Date(), source: "live_activity"),
            ],
            to: [card],
            calendar: calendar
        )
        #expect(!didChange)
        #expect(result == [card])
    }

    // MARK: - Quick adds

    @Test func quickAddCreatesTodoCardWithMatchingCompositeId() {
        let quickAdd = PendingQuickAdd(
            id: "shortcut-123",
            text: "Buy stamps",
            target: .todo,
            dateKey: "2026-08-21",
            createdAt: day("2026-08-21").addingTimeInterval(3600 * 9)
        )
        let (result, didChange) = CardMutations.applyQuickAdds([quickAdd], to: [], calendar: calendar)

        #expect(didChange)
        #expect(result.count == 1)
        let card = result[0]
        #expect(card.type == .checklist)
        #expect(card.id == "shortcut-123")
        #expect(card.checklistItems[0].id == "shortcut-123-item-0")
        // The intent publishes "<cardId>:<itemId>" — completion must match it.
        #expect("\(card.id):\(card.checklistItems[0].id)" == "shortcut-123:shortcut-123-item-0")
        #expect(card.showOnLockScreen)
        #expect(card.dayKey(calendar: calendar) == "2026-08-21")
    }

    @Test func quickAddMultiLineCreatesMultipleCardsWithCompositeIds() {
        let quickAdd = PendingQuickAdd(
            id: "shortcut-multiline",
            text: "- Buy milk\n2. Call doctor\n\n* Read a book",
            target: .todo,
            dateKey: "2026-08-21",
            createdAt: day("2026-08-21").addingTimeInterval(3600 * 9)
        )
        let (result, didChange) = CardMutations.applyQuickAdds([quickAdd], to: [], calendar: calendar)

        #expect(didChange)
        #expect(result.count == 3)
        #expect(result[0].id == "shortcut-multiline-0")
        #expect(result[0].checklistItems[0].id == "shortcut-multiline-0-item-0")
        #expect(result[0].checklistItems[0].text == "Buy milk")
        #expect(result[1].id == "shortcut-multiline-1")
        #expect(result[1].checklistItems[0].id == "shortcut-multiline-1-item-0")
        #expect(result[1].checklistItems[0].text == "Call doctor")
        #expect(result[2].id == "shortcut-multiline-2")
        #expect(result[2].checklistItems[0].id == "shortcut-multiline-2-item-0")
        #expect(result[2].checklistItems[0].text == "Read a book")
    }

    @Test func quickCaptureServiceParsesBulletsAndCleansMemo() {
        let lines = QuickCaptureService.parseTodoLines("• First item\n- Second item\n1. Third item\n   \n Fourth item ")
        #expect(lines == ["First item", "Second item", "Third item", "Fourth item"])

        let memo = QuickCaptureService.cleanMemoText("\n\n  Hello World  \nLine 2\n\n")
        #expect(memo == "Hello World\nLine 2")
    }

    @Test func quickAddMemoUnpinsThePreviousMemo() {
        let existing = Card(
            id: "old-memo",
            title: "Old",
            type: .quickNote,
            isPinned: true,
            showOnLockScreen: true,
            createdAt: day("2026-08-20"),
            updatedAt: day("2026-08-20")
        )
        let quickAdd = PendingQuickAdd(
            id: "shortcut-9",
            text: "Call the clinic\nsecond line",
            target: .memo,
            dateKey: "2026-08-21",
            createdAt: day("2026-08-21")
        )
        let (result, _) = CardMutations.applyQuickAdds([quickAdd], to: [existing], calendar: calendar)

        #expect(result.count == 2)
        #expect(!result[0].isPinned, "only one memo may be pinned")
        #expect(!result[0].showOnLockScreen)
        #expect(result[1].isPinned)
        #expect(result[1].title == "Call the clinic", "title is the first non-empty line")
        #expect(result[1].body.contains("second line"))
    }

    @Test func quickAddSkipsDuplicateIds() {
        let existing = todoCard(id: "shortcut-1", day: "2026-08-21", items: [])
        let quickAdd = PendingQuickAdd(
            id: "shortcut-1",
            text: "Duplicate",
            target: .todo,
            dateKey: "2026-08-21",
            createdAt: day("2026-08-21")
        )
        let (result, didChange) = CardMutations.applyQuickAdds([quickAdd], to: [existing], calendar: calendar)
        #expect(!didChange)
        #expect(result.count == 1)
    }

    @Test func memoTitleIsCappedAtTwentyCharacters() {
        let long = String(repeating: "a", count: 40)
        #expect(CardMutations.memoTitle(from: long).count == 20)
        #expect(CardMutations.memoTitle(from: "\n\n  hello  \nworld") == "hello")
    }

    // MARK: - Rollover

    @Test func rollsUnfinishedTodosOntoToday() {
        let yesterday = todoCard(id: "c1", day: "2026-08-20", items: [
            ChecklistItem(id: "i1", text: "Unfinished")
        ])
        let (result, didChange) = CardMutations.rollOverIncompleteTodos(
            [yesterday],
            calendar: calendar,
            now: day("2026-08-21")
        )

        #expect(didChange)
        #expect(result.count == 1, "a card with no history simply moves")
        #expect(result[0].id == "c1")
        #expect(result[0].dayKey(calendar: calendar) == "2026-08-21")
    }

    @Test func splitsCardThatHasBothFinishedAndUnfinishedWork() {
        let yesterday = todoCard(id: "c1", day: "2026-08-20", items: [
            ChecklistItem(id: "i1", text: "Done", isDone: true),
            ChecklistItem(id: "i2", text: "Not done"),
        ])
        let (result, didChange) = CardMutations.rollOverIncompleteTodos(
            [yesterday],
            calendar: calendar,
            now: day("2026-08-21"),
            idFactory: { "rolled-\($0)" }
        )

        #expect(didChange)
        #expect(result.count == 2)
        let history = result[0]
        #expect(history.id == "c1")
        #expect(history.dayKey(calendar: calendar) == "2026-08-20", "history stays on its day")
        #expect(history.checklistItems.map(\.text) == ["Done"])

        let carried = result[1]
        #expect(carried.id == "rolled-0")
        #expect(carried.dayKey(calendar: calendar) == "2026-08-21")
        #expect(carried.checklistItems.map(\.text) == ["Not done"])
        #expect(carried.title == "Not done")
        #expect(carried.lastActivatedAt == nil)
    }

    @Test func leavesTodayAndNonChecklistCardsAlone() {
        let today = todoCard(id: "c1", day: "2026-08-21", items: [ChecklistItem(id: "i1", text: "Today")])
        let memo = Card(
            id: "m1",
            title: "Memo",
            type: .quickNote,
            targetDateTime: day("2026-08-01"),
            createdAt: day("2026-08-01"),
            updatedAt: day("2026-08-01")
        )
        let (result, didChange) = CardMutations.rollOverIncompleteTodos(
            [today, memo],
            calendar: calendar,
            now: day("2026-08-21")
        )
        #expect(!didChange)
        #expect(result.count == 2)
    }

    // MARK: - Recurrence

    @Test func createsTodaysOccurrenceForDailyTodo() {
        let seed = todoCard(id: "c1", day: "2026-08-19", items: [
            ChecklistItem(id: "i1", text: "Stretch", isDone: true, recurrence: .daily, recurrenceId: "series-1")
        ])
        let (result, didChange) = CardMutations.createRecurringTodosForToday(
            [seed],
            calendar: calendar,
            now: day("2026-08-21"),
            idFactory: { "repeat-\($0)" }
        )

        #expect(didChange)
        #expect(result.count == 2)
        let occurrence = result[1]
        #expect(occurrence.id == "repeat-0")
        #expect(occurrence.dayKey(calendar: calendar) == "2026-08-21")
        #expect(occurrence.checklistItems.count == 1)
        #expect(occurrence.checklistItems[0].id == "repeat-0-item-0")
        #expect(!occurrence.checklistItems[0].isDone, "a new occurrence starts unfinished")
        #expect(occurrence.checklistItems[0].completedAt == nil)
        #expect(occurrence.checklistItems[0].recurrenceId == "series-1")
    }

    @Test func doesNotDuplicateAnOccurrenceThatAlreadyExists() {
        let seed = todoCard(id: "c1", day: "2026-08-19", items: [
            ChecklistItem(id: "i1", text: "Stretch", recurrence: .daily, recurrenceId: "series-1")
        ])
        let today = todoCard(id: "c2", day: "2026-08-21", items: [
            ChecklistItem(id: "i2", text: "Stretch", recurrence: .daily, recurrenceId: "series-1")
        ])
        let (result, didChange) = CardMutations.createRecurringTodosForToday(
            [seed, today],
            calendar: calendar,
            now: day("2026-08-21")
        )
        #expect(!didChange)
        #expect(result.count == 2)
    }

    @Test func weekdayRecurrenceSkipsTheWeekend() {
        // 2026-08-22 is a Saturday.
        let seed = todoCard(id: "c1", day: "2026-08-20", items: [
            ChecklistItem(id: "i1", text: "Standup", recurrence: .weekdays, recurrenceId: "series-1")
        ])
        let (saturday, changedOnSaturday) = CardMutations.createRecurringTodosForToday(
            [seed], calendar: calendar, now: day("2026-08-22")
        )
        #expect(!changedOnSaturday)
        #expect(saturday.count == 1)

        let (monday, changedOnMonday) = CardMutations.createRecurringTodosForToday(
            [seed], calendar: calendar, now: day("2026-08-24")
        )
        #expect(changedOnMonday)
        #expect(monday.count == 2)
    }

    @Test func weeklyRecurrenceLandsOnMultiplesOfSevenDays() {
        let seed = todoCard(id: "c1", day: "2026-08-07", items: [
            ChecklistItem(id: "i1", text: "Review", recurrence: .weekly, recurrenceId: "series-1")
        ])
        let (sixDaysLater, changedEarly) = CardMutations.createRecurringTodosForToday(
            [seed], calendar: calendar, now: day("2026-08-13")
        )
        #expect(!changedEarly)
        #expect(sixDaysLater.count == 1)

        let (sevenDaysLater, changedOnDue) = CardMutations.createRecurringTodosForToday(
            [seed], calendar: calendar, now: day("2026-08-14")
        )
        #expect(changedOnDue)
        #expect(sevenDaysLater.count == 2)
    }

    @Test func sortsNewestFirst() {
        let older = todoCard(id: "old", day: "2026-08-19", items: [])
        let newer = todoCard(id: "new", day: "2026-08-21", items: [])
        #expect(CardMutations.sorted([older, newer]).map(\.id) == ["new", "old"])
    }
}

@Suite("Review deletion regression")
struct ReviewDeletionTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ offset: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 27 + offset))! }
    private func seed(_ recurrence: TodoRecurrence = .daily, advanced: AdvancedRepeatRule? = nil) -> Card {
        Card(id: "dog", title: "Walk my dog", type: .checklist,
             checklistItems: [ChecklistItem(id: "dog-item", text: "Walk my dog", recurrence: recurrence, advancedRepeat: advanced),
                              ChecklistItem(id: "sibling", text: "Keep this task")],
             targetDateTime: day(0), createdAt: day(0), updatedAt: day(0))
    }
    private func reload(_ cards: [Card], _ offset: Int) throws -> [Card] {
        let restored = try JSONDecoder().decode([Card].self, from: JSONEncoder().encode(cards))
        let rolled = CardMutations.rollOverIncompleteTodos(restored, calendar: calendar, now: day(offset)).cards
        return CardMutations.createRecurringTodosForToday(rolled, calendar: calendar, now: day(offset)).cards
    }
    private func dogItems(_ cards: [Card]) -> [ChecklistItem] {
        cards.flatMap(\.checklistItems).filter { $0.effectiveRecurrenceId == "dog-item" }
    }
    @Test func oldCardOnlyDeletionReproducesReview() throws {
        var history = seed(); history.checklistItems[0].isDone = true
        history.checklistItems.removeLast()
        let today = CardMutations.createRecurringTodosForToday([history], calendar: calendar, now: day(1)).cards
        let oldDelete = today.filter { $0.id == history.id }
        #expect(dogItems(try reload(oldDelete, 2)).count == 2)
    }
    @Test func ordinaryDeletionPreservesSiblingAndNeverReturns() throws {
        var unrelated = seed(.none)
        unrelated.id = "unrelated"
        unrelated.title = "Custom list title"
        unrelated.checklistItems = [ChecklistItem(id: "other-item", text: "Other task")]
        let result = CardMutations.deleteTodo([seed(.none), unrelated], cardID: "dog", itemID: "dog-item", on: day(0), scope: .occurrence, calendar: calendar)
        #expect(result.contains(unrelated))
        for offset in [0, 1, 2, 7] {
            let loaded = try reload(result, offset)
            #expect(dogItems(loaded).isEmpty)
            #expect(loaded.flatMap(\.checklistItems).contains { $0.id == "sibling" })
        }
    }
    @Test func deleteOnlyOccurrenceSurvivesRestartAndNextRepeatReturns() throws {
        let result = CardMutations.deleteTodo([seed()], cardID: "dog", itemID: "dog-item", on: day(0), scope: .occurrence, calendar: calendar)
        #expect(dogItems(try reload(result, 0)).isEmpty)
        #expect(dogItems(try reload(result, 1)).count == 1)
        #expect(result.first?.recurrenceRules.first?.excludedDateKeys == ["2026-10-27"])
    }
    @Test func stoppingSeriesSurvivesOldSourcesAndFuturePreview() throws {
        var history = seed(); history.checklistItems[0].isDone = true; history.checklistItems.removeLast()
        let today = CardMutations.createRecurringTodosForToday([history], calendar: calendar, now: day(1)).cards
        let current = today.first { $0.id != history.id }!
        let result = CardMutations.deleteTodo(today, cardID: current.id, itemID: current.checklistItems[0].id, on: day(1), scope: .future, calendar: calendar)
        for offset in [1, 2, 3, 8, 30] {
            let loaded = try reload(result, offset)
            #expect(dogItems(loaded).count == 1)
            #expect(dogItems(loaded).allSatisfy { $0.isDone })
            let future = CardMutations.calendarTodos(loaded, on: day(offset + 1), calendar: calendar, now: day(offset))
            #expect(dogItems(future).isEmpty)
        }
    }
    @Test func deleteEntireSeriesRemovesHistoryAndRules() throws {
        var history = seed(); history.checklistItems[0].isDone = true
        let today = CardMutations.createRecurringTodosForToday([history], calendar: calendar, now: day(1)).cards
        let current = today.first { $0.id != history.id }!
        let result = CardMutations.deleteTodo(today, cardID: current.id, itemID: current.checklistItems[0].id, on: day(1), scope: .series, calendar: calendar)
        #expect(dogItems(try reload(result, 8)).isEmpty)
        #expect(result.flatMap(\.recurrenceRules).isEmpty)
        #expect(result.flatMap(\.checklistItems).contains { $0.id == "sibling" })
    }
    @Test func excludedDateAlsoBlocksStaleIncompleteRollover() throws {
        var history = seed()
        let future = CardMutations.createRecurringTodosForToday([history], calendar: calendar, now: day(1)).cards.last!
        history.checklistItems.removeLast()
        let result = CardMutations.deleteTodo([history, future], cardID: future.id, itemID: future.checklistItems[0].id, on: day(1), scope: .occurrence, calendar: calendar)
        #expect(dogItems(try reload(result, 1)).isEmpty)
        #expect(!dogItems(try reload(result, 2)).isEmpty)
    }
    @Test func allSupportedRulesHonorStopAndExclusions() throws {
        let variants: [Card] = TodoRecurrence.allCases.filter { $0 != .none }.map { seed($0) }
            + [seed(.none, advanced: .biweekly(3)), seed(.none, advanced: .selectedWeekdays([2, 4, 6])), seed(.none, advanced: .everyNDays(3))]
        for card in variants {
            let stopped = CardMutations.deleteTodo([card], cardID: card.id, itemID: "dog-item", on: day(0), scope: .future, calendar: calendar)
            let excluded = CardMutations.deleteTodo([card], cardID: card.id, itemID: "dog-item", on: day(0), scope: .occurrence, calendar: calendar)
            #expect(dogItems(try reload(excluded, 0)).isEmpty)
            for offset in 1...21 { #expect(dogItems(try reload(stopped, offset)).isEmpty) }
        }
    }
}

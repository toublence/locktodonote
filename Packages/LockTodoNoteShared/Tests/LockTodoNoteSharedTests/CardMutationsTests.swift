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

import Foundation
import Testing
@testable import LockTodoNoteShared

@Suite("Calendar recurring task projection")
struct CalendarRecurrenceTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }

    private func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: number))!
    }

    private func seed(_ id: String = "seed", recurrence: TodoRecurrence = .daily,
                      advanced: AdvancedRepeatRule? = nil) -> Card {
        Card(id: id, title: "Exercise", type: .checklist,
             checklistItems: [ChecklistItem(id: id + "-item", text: "Exercise", recurrence: recurrence,
                                           advancedRepeat: advanced, recurrenceAnchorDate: day(15))],
             targetDateTime: day(15), createdAt: day(15), updatedAt: day(15))
    }

    private func todos(_ cards: [Card], on number: Int) -> [Card] {
        CardMutations.calendarTodos(cards, on: day(number), calendar: calendar, now: day(15))
    }

    @Test func dailyAppearsEveryFutureDayWithIndependentCompletion() {
        let original = seed()
        for number in 16...31 {
            let projected = todos([original], on: number)
            #expect(projected.count == 1)
            #expect(projected[0].day(calendar: calendar) == day(number))
        }
        var completed = todos([original], on: 16)[0]
        completed.checklistItems[0].isDone = true
        let stored = [original, completed]
        #expect(todos(stored, on: 16).count == 1)
        #expect(todos(stored, on: 16)[0].checklistItems[0].isDone)
        #expect(!todos(stored, on: 17)[0].checklistItems[0].isDone)
        #expect(original.checklistItems.count == 1)
    }

    @Test func stableIdentityWhenAnotherSeriesIsMaterialized() {
        let originals = [seed("a"), seed("b")]
        let first = todos(originals, on: 16)
        let after = todos(originals + [first[0]], on: 16)
        #expect(Set(first.map(\.id)) == Set(after.map(\.id)))
        #expect(first.map(\.checklistItems).flatMap { $0 }.allSatisfy { $0.recurrenceId != nil })
    }

    @Test func weeklyWeekdaysAndAdvancedRespectTheirRules() {
        #expect(todos([seed(recurrence: .weekly)], on: 16).isEmpty)
        #expect(todos([seed(recurrence: .weekly)], on: 22).count == 1)
        #expect(todos([seed(recurrence: .weekdays)], on: 17).isEmpty)
        #expect(todos([seed(recurrence: .weekdays)], on: 19).count == 1)
        let advanced = seed(recurrence: .none, advanced: .everyNDays(3))
        #expect(todos([advanced], on: 16).isEmpty)
        #expect(todos([advanced], on: 18).count == 1)
        #expect(todos([advanced], on: 21).count == 1)
    }

    @Test func neverInventsPastOccurrencesOrAppleReminderCopies() {
        #expect(todos([seed()], on: 14).isEmpty)
        #expect(todos([seed()], on: 15).count == 1)
        let apple = seed(AppleReminderMirror.cardID(for: "external"))
        #expect(todos([apple], on: 16).isEmpty)
        #expect(todos([seed(recurrence: .none)], on: 16).isEmpty)
    }
}

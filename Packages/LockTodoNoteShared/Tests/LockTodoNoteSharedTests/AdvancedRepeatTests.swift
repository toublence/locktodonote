import Foundation
import Testing
@testable import LockTodoNoteShared

@Suite("Advanced repeat")
struct AdvancedRepeatTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return result
    }
    private func day(_ value: String, calendar: Calendar? = nil) -> Date {
        // Build in the supplied time zone, independent of the machine's current zone.
        let parts = value.split(separator: "-").map { Int($0)! }
        return (calendar ?? self.calendar).date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2]
        ))!
    }

    @Test func selectedWeekdaysAndStartBoundary() {
        let rule = AdvancedRepeatRule.selectedWeekdays([2, 4, 6])
        let anchor = day("2026-10-12")
        #expect(rule.isDue(seedDate: anchor, on: day("2026-10-14"), calendar: calendar))
        #expect(rule.isDue(seedDate: anchor, on: day("2026-10-16"), calendar: calendar))
        #expect(!rule.isDue(seedDate: anchor, on: day("2026-10-15"), calendar: calendar))
        #expect(!rule.isDue(seedDate: anchor, on: day("2026-10-09"), calendar: calendar))
    }

    @Test func monthlyLastFridayAcrossLeapFebruary() {
        let rule = AdvancedRepeatRule.monthlyLastWeekday(6)
        let anchor = day("2028-01-01")
        for key in ["2028-01-28", "2028-02-25", "2028-03-31"] {
            #expect(rule.isDue(seedDate: anchor, on: day(key), calendar: calendar))
        }
        #expect(!rule.isDue(seedDate: anchor, on: day("2028-03-24"), calendar: calendar))
    }

    @Test func biweeklyUsesFirstSelectedWeekdayNotLocaleWeekNumber() {
        let rule = AdvancedRepeatRule.biweekly(3)
        let anchor = day("2026-12-30")
        #expect(rule.firstOccurrence(onOrAfter: anchor, calendar: calendar) == day("2027-01-05"))
        #expect(rule.isDue(seedDate: anchor, on: day("2027-01-05"), calendar: calendar))
        #expect(!rule.isDue(seedDate: anchor, on: day("2027-01-12"), calendar: calendar))
        #expect(rule.isDue(seedDate: anchor, on: day("2027-01-19"), calendar: calendar))
    }

    @Test func everyThreeDaysCrossesMonthAndYear() {
        let rule = AdvancedRepeatRule.everyNDays(3)
        let anchor = day("2026-12-30")
        #expect(rule.isDue(seedDate: anchor, on: day("2027-01-02"), calendar: calendar))
        #expect(!rule.isDue(seedDate: anchor, on: day("2027-01-01"), calendar: calendar))
        #expect(rule.isDue(seedDate: anchor, on: day("2027-01-05"), calendar: calendar))
    }

    @Test func intervalsUseCalendarDaysAcrossDST() {
        var local = calendar
        local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let anchor = day("2026-03-07", calendar: local)
        #expect(AdvancedRepeatRule.everyNDays(3).isDue(
            seedDate: anchor, on: day("2026-03-10", calendar: local), calendar: local
        ))
        #expect(AdvancedRepeatRule.biweekly(1).isDue(
            seedDate: anchor, on: day("2026-03-22", calendar: local), calendar: local
        ))
    }

    @Test func rejectsInvalidRules() {
        for rule in [AdvancedRepeatRule.selectedWeekdays([]), .selectedWeekdays([2, 2]),
                     .monthlyLastWeekday(8), .biweekly(0), .everyNDays(0), .everyNDays(366)] {
            #expect(!rule.isValid)
            #expect(!rule.isDue(seedDate: day("2026-10-15"), on: day("2026-10-15"), calendar: calendar))
            #expect(rule.firstOccurrence(onOrAfter: day("2026-10-15"), calendar: calendar) == nil)
        }
    }

    @Test func itemRoundTripAndLegacyDecode() throws {
        let item = ChecklistItem(id: "i", text: "Exercise", advancedRepeat: .selectedWeekdays([2, 4, 6]),
                                 recurrenceAnchorDate: day("2026-10-12"))
        let decoded = try JSONDecoder().decode(ChecklistItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
        let legacy = try JSONDecoder().decode(ChecklistItem.self, from: Data(
            #"{"id":"legacy","text":"Walk","recurrence":"daily"}"#.utf8
        ))
        #expect(legacy.advancedRepeat == nil)
        #expect(legacy.isRecurrenceDue(seedDate: day("2026-10-12"), on: day("2026-10-13"), calendar: calendar))
    }

    @Test func createsOnlyDueOccurrenceAndDoesNotDuplicate() {
        let anchor = day("2026-10-12")
        let card = Card(id: "c", title: "Exercise", type: .checklist,
                        checklistItems: [ChecklistItem(id: "i", text: "Exercise", isDone: true,
                            advancedRepeat: .selectedWeekdays([2, 4, 6]), recurrenceAnchorDate: anchor)],
                        targetDateTime: anchor, createdAt: anchor, updatedAt: anchor)
        #expect(!CardMutations.createRecurringTodosForToday([card], calendar: calendar, now: day("2026-10-15")).didChange)
        let created = CardMutations.createRecurringTodosForToday([card], calendar: calendar, now: day("2026-10-16"))
        #expect(created.cards.count == 2)
        #expect(created.cards.last?.checklistItems.first?.isDone == false)
        #expect(created.cards.last?.checklistItems.first?.advancedRepeat == .selectedWeekdays([2, 4, 6]))
        #expect(!CardMutations.createRecurringTodosForToday(created.cards, calendar: calendar, now: day("2026-10-16")).didChange)
    }

    @Test func tomorrowProjectionUsesAdvancedRule() {
        let anchor = day("2026-10-12")
        let card = Card(id: "c", title: "Exercise", type: .checklist,
                        checklistItems: [ChecklistItem(id: "i", text: "Exercise", isDone: true,
                            advancedRepeat: .selectedWeekdays([2, 4, 6]), recurrenceAnchorDate: anchor)],
                        targetDateTime: anchor, createdAt: anchor, updatedAt: anchor)
        let strings = DashboardStrings(noEvents: "", hiddenContent: "", checkInApp: "", dDayToday: "",
                                       dPlusPrefix: "", timePassed: "", hoursMinutesRemaining: "", remainingTasks: "")
        let snapshot = DashboardComposer(strings: strings, calendar: calendar).compose(
            cards: [card], settings: LockScreenSettings(), now: day("2026-10-15")
        )
        #expect(snapshot.calendarDays.first { $0.id == "2026-10-16" }?.todoItems.map(\.text) == ["Exercise"])
    }
}

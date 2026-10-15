import Foundation
import Testing
@testable import LockTodoNoteShared

@Suite("Smart Lock Screen schedule")
struct SmartLockScreenScheduleTests {
    private let profileID = UUID()
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func rule(start: Int = 540, end: Int = 1080, weekdays: [Int] = [2, 3, 4, 5, 6]) -> SmartLockScreenRule {
        SmartLockScreenRule(name: "Work", profileID: profileID, weekdays: weekdays, startMinute: start, endMinute: end)
    }
    private var profile: LayoutProfile {
        LayoutProfile(id: profileID, name: "Work", settings: LockScreenSettings(template: .dateTodo), colorTheme: "default")
    }

    @Test func startInclusiveAndEndExclusive() {
        let work = rule()
        #expect(!work.matches(date(15, 8, 59), calendar: calendar))
        #expect(work.matches(date(15, 9), calendar: calendar))
        #expect(work.matches(date(15, 17, 59), calendar: calendar))
        #expect(!work.matches(date(15, 18), calendar: calendar))
        #expect(!work.matches(date(17, 12), calendar: calendar))
    }

    @Test func threeSlotsSelectTheRightSavedLayout() {
        let morning = rule(start: 360, end: 540)
        let work = rule()
        let evening = rule(start: 1080, end: 1320)
        let schedule = SmartLockScreenSchedule(isEnabled: true, rules: [morning, work, evening])
        for (hour, expected) in [(7, morning.id), (12, work.id), (20, evening.id)] {
            #expect(schedule.activeRule(at: date(15, hour), isPro: true, profiles: [profile], calendar: calendar)?.id == expected)
        }
        #expect(schedule.activeRule(at: date(15, 23), isPro: true, profiles: [profile], calendar: calendar) == nil)
    }

    @Test func overnightCarriesTheStartingWeekday() {
        let fridayNight = rule(start: 1320, end: 360, weekdays: [6])
        #expect(fridayNight.matches(date(16, 23), calendar: calendar))
        #expect(fridayNight.matches(date(17, 5, 59), calendar: calendar))
        #expect(!fridayNight.matches(date(17, 6), calendar: calendar))
        #expect(!fridayNight.matches(date(16, 5), calendar: calendar))
    }

    @Test func overnightSundayWrapsToMonday() {
        let sunday = rule(start: 1320, end: 120, weekdays: [1])
        #expect(sunday.matches(date(19, 1), calendar: calendar))
        #expect(!sunday.matches(date(19, 2), calendar: calendar))
    }

    @Test func adjacentSlotsDoNotOverlap() {
        #expect(!rule(start: 360, end: 540).overlaps(rule()))
        #expect(rule().overlaps(rule(start: 1079, end: 1200)))
        #expect(!rule(weekdays: [2]).overlaps(rule(weekdays: [3])))
    }

    @Test func overnightOverlapIncludesFollowingDay() {
        #expect(rule(start: 1320, end: 360, weekdays: [6]).overlaps(rule(start: 300, end: 480, weekdays: [7])))
        #expect(!rule(start: 1320, end: 360, weekdays: [6]).overlaps(rule(start: 360, end: 480, weekdays: [7])))
    }

    @Test func freeDisabledAndMissingProfilesFallBack() {
        let work = rule()
        var schedule = SmartLockScreenSchedule(isEnabled: true, rules: [work])
        #expect(schedule.activeRule(at: date(15, 12), isPro: false, profiles: [profile], calendar: calendar) == nil)
        #expect(schedule.activeRule(at: date(15, 12), isPro: true, profiles: [], calendar: calendar) == nil)
        schedule.isEnabled = false
        #expect(schedule.activeRule(at: date(15, 12), isPro: true, profiles: [profile], calendar: calendar) == nil)
        var paused = work; paused.isEnabled = false
        #expect(!paused.matches(date(15, 12), calendar: calendar))
        #expect(!paused.overlaps(work))
    }

    @Test func rejectsInvalidTimesAndEmptyWeekdays() {
        #expect(!rule(start: 540, end: 540).isValid)
        #expect(!rule(start: -1).isValid)
        #expect(!rule(end: 1440).isValid)
        #expect(!rule(weekdays: []).isValid)
        #expect(!rule(weekdays: [8]).isValid)
    }

    @Test func filtersMixedCardsAndKeepsRecurringSeries() {
        let created = date(15, 9)
        let card = Card(id: "mixed", title: "Personal secret", type: .checklist, checklistItems: [
            ChecklistItem(id: "personal", text: "Personal secret"),
            ChecklistItem(id: "work-today", text: "Work task", recurrence: .daily, recurrenceId: "work-series")
        ], createdAt: created, updatedAt: created)
        let memo = Card(id: "personal-note", title: "Personal note", type: .quickNote, createdAt: created, updatedAt: created)
        var work = rule(); work.todoSeriesIDs = ["work-series"]; work.memoCardIDs = []
        let filtered = work.filteredCards([card, memo])
        #expect(filtered.count == 1)
        #expect(filtered.first?.checklistItems.map(\.text) == ["Work task"])
        #expect(filtered.first?.title == "Work task")
        #expect(card.checklistItems.count == 2)
        work.todoSeriesIDs = []
        #expect(work.filteredCards([card]).isEmpty)
        work.todoSeriesIDs = nil; work.memoCardIDs = nil
        #expect(work.filteredCards([card, memo]).count == 2)
    }

    @Test func preservesCodableAndExistingProfileFormat() throws {
        let schedule = SmartLockScreenSchedule(isEnabled: true, rules: [rule()])
        let decoded = try JSONDecoder().decode(SmartLockScreenSchedule.self, from: JSONEncoder().encode(schedule))
        #expect(decoded.rules == schedule.rules)
        let decodedProfile = try JSONDecoder().decode(LayoutProfile.self, from: JSONEncoder().encode(profile))
        #expect(decodedProfile.id == profileID)
        #expect(decodedProfile.settings == profile.settings)
        #expect(decoded.rules.first?.todoSeriesIDs == nil)
    }

    @Test func timelineIncludesBoundariesAndMidnightWithoutPastEntries() {
        let schedule = SmartLockScreenSchedule(isEnabled: true, rules: [rule()])
        let dates = schedule.transitionDates(after: date(15, 10), calendar: calendar)
        #expect(dates.contains(date(15, 18)))
        #expect(dates.contains(date(16, 0)))
        #expect(dates.contains(date(16, 9)))
        #expect(!dates.contains(date(15, 9)))
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
    }

    @Test func localTimesSurviveDST() {
        var local = calendar; local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let before = local.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 20))!
        let schedule = SmartLockScreenSchedule(isEnabled: true, rules: [rule(weekdays: [1, 2, 3, 4, 5, 6, 7])])
        let dates = schedule.transitionDates(after: before, calendar: local)
        #expect(dates.contains(local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9))!))
        #expect(dates.contains(local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 18))!))
        #expect(dates.allSatisfy { $0 > before })
    }
}

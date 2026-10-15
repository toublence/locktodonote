import Foundation
import Testing
@testable import LockTodoNoteShared

@Suite("Smart Quick Add")
struct SmartQuickAddParserTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private var now: Date { date(15, hour: 10) }
    private func parse(_ text: String) -> SmartTodo {
        SmartQuickAddParser.parse(text, referenceDate: now, calendar: calendar)[0]
    }

    @Test func koreanAppointmentExtractsDateTimeAndTitle() {
        let result = parse("내일 오후 3시 병원 예약")
        #expect(result.text == "병원 예약")
        #expect(result.scheduledDate == date(16, hour: 15))
        #expect(result.dueDate == date(16, hour: 15))
        #expect(result.hasDueTime)
        #expect(result.card(id: "c", createdAt: now).checklistItems[0].displayText(calendar: calendar) == "15:00 병원 예약")
    }

    @Test func mondayIsTheWeeklyAnchor() {
        let result = parse("매주 월요일 운동")
        #expect(result.text == "운동")
        #expect(result.recurrence == .weekly)
        #expect(result.scheduledDate == date(19))
        #expect(result.card(id: "c", createdAt: now).checklistItems[0].recurrenceAnchorDate == date(19))
    }

    @Test func minutesMidnightAndNoon() {
        #expect(parse("내일 오전 12시 약").scheduledDate == date(16))
        #expect(parse("내일 오후 12시 점심").scheduledDate == date(16, hour: 12))
        #expect(parse("내일 오후 3시 반 병원").scheduledDate == date(16, hour: 15, minute: 30))
        #expect(parse("내일 15:45 병원").scheduledDate == date(16, hour: 15, minute: 45))
    }

    @Test func englishInputUsesTheSamePipeline() {
        let result = parse("tomorrow 3pm appointment")
        #expect(result.text == "appointment")
        #expect(result.scheduledDate == date(16, hour: 15))
        #expect(parse("every Monday exercise").scheduledDate == date(19))
    }

    @Test func relativeAndAbsoluteDates() {
        #expect(parse("모레 장보기").scheduledDate == date(17))
        #expect(parse("3일 후 서류 제출").scheduledDate == date(18))
        #expect(parse("2026-10-20 서류 제출").scheduledDate == date(20))
        #expect(parse("10월 20일 서류 제출").scheduledDate == date(20))
        #expect(parse("다음 주 월요일 운동").scheduledDate == date(19))
    }

    @Test func explicitDateAndRecurrenceWin() {
        let result = SmartQuickAddParser.parse(
            "내일 오후 3시 병원", referenceDate: now, explicitDate: date(20),
            recurrenceOverride: TodoRecurrence.none, calendar: calendar
        )[0]
        #expect(result.scheduledDate == date(20, hour: 15))
        let weekly = SmartQuickAddParser.parse(
            "매주 월요일 운동", referenceDate: now, recurrenceOverride: TodoRecurrence.none, calendar: calendar
        )[0]
        #expect(weekly.recurrence == .none)
    }

    @Test func optOutPreservesTheSentence() {
        let text = "내일 오후 3시 병원 예약"
        let result = SmartQuickAddParser.parse(text, referenceDate: now, enabled: false, calendar: calendar)[0]
        #expect(result.text == text)
        #expect(result.dueDate == nil)
        #expect(!result.recognized)
    }

    @Test func invalidOrAmbiguousSchedulesAreNotPartiallyApplied() {
        for text in [
            "2026-02-30 예약", "내일 오후 25시 병원", "내일 오후 3시 75분 병원",
            "매주 월요일 수요일 운동", "내일 모레 운동", "매월 1일 월세", "내일배움카드 신청",
        ] {
            let result = parse(text)
            #expect(result.text == text)
            #expect(!result.recognized)
        }
    }

    @Test func timeOnlyRollsForwardButExplicitTodayDoesNot() {
        #expect(parse("오전 9시 약").scheduledDate == date(16, hour: 9))
        #expect(parse("오늘 오전 9시 약").scheduledDate == date(15, hour: 9))
        #expect(parse("매일 오전 9시 약").scheduledDate == date(16, hour: 9))
    }

    @Test func weekdaysSkipTheWeekend() {
        let result = SmartQuickAddParser.parse(
            "매일 운동\n매주 평일 오전 9시 출근",
            referenceDate: date(16, hour: 18), calendar: calendar
        )
        #expect(result[1].scheduledDate == date(19, hour: 9))
        #expect(result[1].recurrence == .weekdays)
    }

    @Test func multilineDatesAndQueuedRoundTripStayFrozen() {
        let rows = SmartQuickAddParser.parse(
            "내일 오후 3시 병원\n모레 장보기", referenceDate: now, calendar: calendar
        )
        let queued = PendingQuickAdd(
            id: "capture", text: "내일 오후 3시 병원\n모레 장보기", target: .todo,
            dateKey: "2026-10-16", createdAt: now, smartTodos: rows
        )
        let restored = PendingQuickAdd(dictionary: queued.dictionary)!
        #expect(restored.smartTodos == rows)
        let merged = CardMutations.applyQuickAdds([restored], to: [], calendar: calendar).cards
        #expect(merged.count == 2)
        #expect(merged.first { $0.title == "병원" }?.targetDateTime == date(16, hour: 15))
        #expect(merged.first { $0.title == "장보기" }?.targetDateTime == date(17))
        #expect(!CardMutations.applyQuickAdds([restored], to: merged, calendar: calendar).didChange)
    }

    @Test func legacyQueueIsNotReinterpreted() {
        let queued = PendingQuickAdd(
            id: "legacy", text: "내일 병원", target: .todo,
            dateKey: "2026-10-16", createdAt: now
        )
        let card = CardMutations.applyQuickAdds([queued], to: [], calendar: calendar).cards[0]
        #expect(card.title == "내일 병원")
        #expect(card.day(calendar: calendar) == date(16))
    }

    @Test func rolloverDoesNotMoveAWeeklyRuleToTuesday() {
        let card = SmartQuickAddParser.parse(
            "매주 월요일 오후 3시 운동", referenceDate: now, calendar: calendar
        )[0].card(id: "weekly", createdAt: now)
        let moved = CardMutations.rollOverIncompleteTodos([card], calendar: calendar, now: date(20)).cards
        var completed = moved[0]
        completed.checklistItems[0] = completed.checklistItems[0].markingDone(at: date(20), source: "app")
        let monday = CardMutations.createRecurringTodosForToday(
            [completed], calendar: calendar, now: date(26)
        )
        #expect(monday.didChange)
        let added = monday.cards.first { $0.id != "weekly" }!
        #expect(added.checklistItems[0].dueDate == date(26, hour: 15))
    }

    @Test func oldCardJSONStillDecodesWithoutNewMetadata() throws {
        let card = Card(
            id: "native", title: "Native", type: .checklist,
            checklistItems: [ChecklistItem(id: "item", text: "Native")], createdAt: now, updatedAt: now
        )
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        var items = try #require(object["checklistItems"] as? [[String: Any]])
        items[0].removeValue(forKey: "recurrenceAnchorDate")
        items[0].removeValue(forKey: "hasDueTime")
        object["checklistItems"] = items
        let decoded = try JSONDecoder().decode(Card.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!decoded.checklistItems[0].hasDueTime)
        #expect(decoded.checklistItems[0].recurrenceAnchorDate == nil)
    }
}

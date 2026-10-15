import Foundation

/// Frozen at capture time so an extension queue drained tomorrow does not
/// reinterpret "tomorrow" a second time. All parsing stays on the device.
public struct SmartTodo: Codable, Hashable, Sendable {
    public let text: String
    public let scheduledDate: Date
    public let dueDate: Date?
    public let hasDueTime: Bool
    public let recurrence: TodoRecurrence
    public let recognized: Bool

    public init(text: String, scheduledDate: Date, dueDate: Date? = nil,
                hasDueTime: Bool = false, recurrence: TodoRecurrence = .none, recognized: Bool = false) {
        self.text = text
        self.scheduledDate = scheduledDate
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.recurrence = recurrence
        self.recognized = recognized
    }

    public func card(id: String, createdAt: Date) -> Card {
        Card(
            id: id, title: text, type: .checklist,
            checklistItems: [ChecklistItem(
                id: "\(id)-item-0", text: text, recurrence: recurrence,
                recurrenceAnchorDate: recurrence == .none ? nil : scheduledDate,
                dueDate: dueDate, hasDueTime: hasDueTime
            )],
            showOnLockScreen: true, targetDateTime: scheduledDate,
            createdAt: createdAt, updatedAt: createdAt
        )
    }
}

public enum SmartQuickAddParser {
    private static let patterns: [String: NSRegularExpression] = [
        "weeklyDay": #"(?i)(?<![\p{L}\p{N}])(?:매주\s*(월요일|화요일|수요일|목요일|금요일|토요일|일요일)|every\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday))(?=$|\s|오전|오후|\d)"#,
        "weekdays": #"(?i)(?<![\p{L}\p{N}])(?:매\s*평일|매주\s*평일|평일마다|every\s+weekday|weekdays)(?=$|\s|오전|오후|\d)"#,
        "daily": #"(?i)(?<![\p{L}\p{N}])(?:매일|every\s+day|daily)(?=$|\s|오전|오후|\d)"#,
        "weekly": #"(?i)(?<![\p{L}\p{N}])(?:매주(?!\s*[월화수목금토일])|weekly)(?=$|\s)"#,
        "relative": #"(?i)(?<![\p{L}\p{N}])(오늘|내일|모레|today|tomorrow)(?=$|\s|오전|오후|\d)"#,
        "offset": #"(?i)(?<![\p{L}\p{N}])(?:([1-9]\d{0,2})\s*일\s*(?:후|뒤)|in\s+([1-9]\d{0,2})\s+days?)(?=$|\s)"#,
        "iso": #"(?<![\p{L}\p{N}])(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?=$|\s)"#,
        "date": #"(?<![\p{L}\p{N}])(?:(\d{4})년\s*)?(\d{1,2})월\s*(\d{1,2})일(?=$|\s|오전|오후)"#,
        "weekday": #"(?i)(?<![\p{L}\p{N}])(?:(다음\s*주|이번\s*주|next)\s*)?(월요일|화요일|수요일|목요일|금요일|토요일|일요일|monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?=$|\s|오전|오후)"#,
        "koreanTime": #"(?<![\p{L}\p{N}])(?:(오전|오후|아침|저녁|밤|낮)\s*)?(\d{1,2})시(?:\s*(반|\d{1,2}\s*분))?(?!\s*\d+\s*분)(?=$|\s)"#,
        "clock": #"(?i)(?<![\p{L}\p{N}])(\d{1,2}):(\d{2})(?:\s*(am|pm))?(?=$|\s)"#,
        "ampm": #"(?i)(?<![\p{L}\p{N}])(\d{1,2})\s*(am|pm)(?=$|\s)"#,
    ].mapValues { try! NSRegularExpression(pattern: $0) }

    public static func parse(
        _ text: String, referenceDate: Date = Date(), defaultDate: Date? = nil,
        explicitDate: Date? = nil, recurrenceOverride: TodoRecurrence? = nil,
        enabled: Bool = true, calendar: Calendar = .current
    ) -> [SmartTodo] {
        QuickCaptureService.parseTodoLines(from: text).map {
            parseLine($0, referenceDate: referenceDate, defaultDate: defaultDate ?? referenceDate,
                      explicitDate: explicitDate, recurrenceOverride: recurrenceOverride,
                      enabled: enabled, calendar: calendar)
        }
    }

    private struct Token {
        let range: Range<String.Index>
        let groups: [String]
    }

    private static func match(_ key: String, in text: String) -> Token? {
        guard let expression = patterns[key],
              let result = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(result.range, in: text) else { return nil }
        let groups = (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        return Token(range: range, groups: groups)
    }

    private static func weekday(_ name: String) -> Int? {
        let names = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]
        let english = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return (names.firstIndex(of: name) ?? english.firstIndex(of: name.lowercased())).map { $0 + 1 }
    }

    private static func parseLine(
        _ original: String, referenceDate: Date, defaultDate: Date, explicitDate: Date?,
        recurrenceOverride: TodoRecurrence?, enabled: Bool, calendar: Calendar
    ) -> SmartTodo {
        let fallbackDate = CardMutations.combine(day: explicitDate ?? defaultDate, time: referenceDate, calendar: calendar)
        let plain = SmartTodo(text: original, scheduledDate: fallbackDate, recurrence: recurrenceOverride ?? .none)
        guard enabled, original.count <= 2_000 else { return plain }
        var text = original
        var parsedDay: Date?
        var rule: TodoRecurrence = .none
        var hour: Int?
        var minute = 0
        var recognized = false
        var weekdaySpecified = false
        var rollPastTimeForward = true
        let today = calendar.startOfDay(for: referenceDate)
        func nextWeekday(_ number: Int, from day: Date) -> Date {
            let difference = (number - calendar.component(.weekday, from: day) + 7) % 7
            return calendar.date(byAdding: .day, value: difference, to: day) ?? day
        }

        if let token = match("weeklyDay", in: text),
           let number = weekday(token.groups.first(where: { !$0.isEmpty }) ?? "") {
            rule = .weekly
            weekdaySpecified = true
            parsedDay = nextWeekday(number, from: today)
            text.removeSubrange(token.range)
            recognized = true
            // Multiple weekdays need a richer rule; never silently pick just one.
            if match("weekday", in: text) != nil { return plain }
        } else {
            for (key, value) in [("weekdays", TodoRecurrence.weekdays), ("daily", .daily), ("weekly", .weekly)] {
                if let token = match(key, in: text) {
                    rule = value
                    text.removeSubrange(token.range)
                    recognized = true
                    break
                }
            }
        }

        if let token = match("relative", in: text) {
            let word = token.groups[0].lowercased()
            let offset = ["내일", "tomorrow"].contains(word) ? 1 : (word == "모레" ? 2 : 0)
            if parsedDay != nil { return plain }
            parsedDay = calendar.date(byAdding: .day, value: offset, to: today)
            rollPastTimeForward = false
            text.removeSubrange(token.range)
            recognized = true
        } else if let token = match("offset", in: text),
                  let offset = Int(token.groups.first(where: { !$0.isEmpty }) ?? "") {
            if parsedDay != nil { return plain }
            parsedDay = calendar.date(byAdding: .day, value: offset, to: today)
            rollPastTimeForward = false
            text.removeSubrange(token.range)
            recognized = true
        } else if let token = match("iso", in: text) ?? match("date", in: text) {
            if parsedDay != nil { return plain }
            let explicitYear = Int(token.groups[0])
            let year = explicitYear ?? calendar.component(.year, from: today)
            guard let month = Int(token.groups[1]), let day = Int(token.groups[2]),
                  let date = validDate(year: year, month: month, day: day, calendar: calendar) else { return plain }
            parsedDay = date
            if explicitYear == nil && date < today {
                parsedDay = validDate(year: year + 1, month: month, day: day, calendar: calendar)
                guard parsedDay != nil else { return plain }
            }
            rollPastTimeForward = false
            text.removeSubrange(token.range)
            recognized = true
        } else if let token = match("weekday", in: text), let number = weekday(token.groups[1]) {
            weekdaySpecified = true
            if parsedDay != nil { return plain }
            let qualifier = token.groups[0].replacingOccurrences(of: " ", with: "").lowercased()
            if qualifier == "다음주" || qualifier == "이번주" {
                let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
                let dayOffset = -mondayOffset + (qualifier == "다음주" ? 7 : 0) + (number + 5) % 7
                parsedDay = calendar.date(byAdding: .day, value: dayOffset, to: today)
                rollPastTimeForward = false
            } else {
                parsedDay = nextWeekday(number, from: today)
                if qualifier == "next", parsedDay == today {
                    parsedDay = calendar.date(byAdding: .day, value: 7, to: today)
                }
            }
            text.removeSubrange(token.range)
            recognized = true
        }

        if let token = match("koreanTime", in: text) {
            guard let value = Int(token.groups[1]) else { return plain }
            let period = token.groups[0]
            // "밤 12시" has an ambiguous day boundary. Keep unsupported day
            // periods verbatim rather than silently interpreting them as noon.
            guard period.isEmpty || ["오전", "오후"].contains(period) else { return plain }
            guard period.isEmpty ? (0...23).contains(value) : (1...12).contains(value) else { return plain }
            hour = period.isEmpty ? value : value % 12 + (["오후", "저녁", "밤", "낮"].contains(period) ? 12 : 0)
            let rawMinute = token.groups[2].replacingOccurrences(of: "분", with: "").trimmingCharacters(in: .whitespaces)
            minute = rawMinute == "반" ? 30 : (Int(rawMinute) ?? 0)
            guard (0...59).contains(minute) else { return plain }
            text.removeSubrange(token.range)
            recognized = true
        } else if let token = match("clock", in: text) {
            guard let value = Int(token.groups[0]), let minutes = Int(token.groups[1]),
                  (0...59).contains(minutes) else { return plain }
            let period = token.groups[2].lowercased()
            guard period.isEmpty ? (0...23).contains(value) : (1...12).contains(value) else { return plain }
            hour = period.isEmpty ? value : value % 12 + (period == "pm" ? 12 : 0)
            minute = minutes
            text.removeSubrange(token.range)
            recognized = true
        } else if let token = match("ampm", in: text) {
            guard let value = Int(token.groups[0]), (1...12).contains(value) else { return plain }
            hour = value % 12 + (token.groups[1].lowercased() == "pm" ? 12 : 0)
            text.removeSubrange(token.range)
            recognized = true
        }
        // Ambiguous multiple schedules are kept verbatim instead of losing words.
        for key in patterns.keys {
            if match(key, in: text) != nil { return plain }
        }
        guard recognized else { return plain }
        rule = recurrenceOverride ?? rule
        var day = calendar.startOfDay(for: explicitDate ?? parsedDay ?? defaultDate)
        if rule == .weekdays && explicitDate == nil {
            while [1, 7].contains(calendar.component(.weekday, from: day)) {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
        }
        var scheduled = day
        if let hour {
            guard let date = setTime(hour: hour, minute: minute, on: day, calendar: calendar) else { return plain }
            scheduled = date
            if explicitDate == nil && rollPastTimeForward && day == today && scheduled < referenceDate {
                day = calendar.date(byAdding: .day, value: (rule == .weekly || weekdaySpecified) ? 7 : 1, to: day) ?? day
                if rule == .weekdays {
                    while [1, 7].contains(calendar.component(.weekday, from: day)) {
                        day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                    }
                }
                guard let date = setTime(hour: hour, minute: minute, on: day, calendar: calendar) else { return plain }
                scheduled = date
            }
        }
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return SmartTodo(
            text: cleaned.isEmpty ? original : cleaned, scheduledDate: scheduled,
            dueDate: scheduled, hasDueTime: hour != nil, recurrence: rule, recognized: true
        )
    }

    private static func validDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func setTime(hour: Int, minute: Int, on date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        guard let result = calendar.date(from: components),
              calendar.component(.hour, from: result) == hour,
              calendar.component(.minute, from: result) == minute else { return nil }
        return result
    }
}

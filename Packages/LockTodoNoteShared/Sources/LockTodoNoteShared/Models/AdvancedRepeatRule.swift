import Foundation

/// Calendar-based rules. Weekdays use Calendar's Sunday = 1 ... Saturday = 7.
public enum AdvancedRepeatRule: Codable, Hashable, Sendable {
    case selectedWeekdays([Int])
    case monthlyLastWeekday(Int)
    case biweekly(Int)
    case everyNDays(Int)

    public var isValid: Bool {
        switch self {
        case .selectedWeekdays(let days):
            !days.isEmpty && Set(days).count == days.count && days.allSatisfy { (1...7).contains($0) }
        case .monthlyLastWeekday(let day), .biweekly(let day): (1...7).contains(day)
        case .everyNDays(let interval): (2...365).contains(interval)
        }
    }

    public func isDue(seedDate: Date, on date: Date, calendar: Calendar = .current) -> Bool {
        guard isValid else { return false }
        let seed = calendar.startOfDay(for: seedDate)
        let target = calendar.startOfDay(for: date)
        guard target >= seed else { return false }
        let weekday = calendar.component(.weekday, from: target)
        switch self {
        case .selectedWeekdays(let days): return days.contains(weekday)
        case .monthlyLastWeekday(let day):
            guard weekday == day,
                  let nextWeek = calendar.date(byAdding: .day, value: 7, to: target) else { return false }
            return !calendar.isDate(target, equalTo: nextWeek, toGranularity: .month)
        case .biweekly(let day):
            let offset = (day - calendar.component(.weekday, from: seed) + 7) % 7
            let elapsed = calendar.dateComponents([.day], from: seed, to: target).day ?? -1
            return weekday == day && elapsed >= offset && (elapsed - offset) % 14 == 0
        case .everyNDays(let interval):
            let elapsed = calendar.dateComponents([.day], from: seed, to: target).day ?? -1
            return elapsed >= 0 && elapsed % interval == 0
        }
    }

    public func firstOccurrence(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        guard isValid else { return nil }
        for offset in 0...31 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if isDue(seedDate: date, on: candidate, calendar: calendar) { return candidate }
        }
        return nil
    }
}

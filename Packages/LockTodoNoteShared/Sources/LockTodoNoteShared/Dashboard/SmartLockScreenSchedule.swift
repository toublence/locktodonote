import Foundation

public struct LayoutProfile: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let settings: LockScreenSettings
    public let colorTheme: String

    public init(id: UUID, name: String, settings: LockScreenSettings, colorTheme: String) {
        self.id = id; self.name = name; self.settings = settings; self.colorTheme = colorTheme
    }
}

public struct SmartLockScreenRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var profileID: UUID
    public var weekdays: [Int]
    public var startMinute: Int
    public var endMinute: Int
    public var isEnabled: Bool
    /// nil = all; [] = none. Repeating occurrences retain their series identity.
    public var todoSeriesIDs: [String]?
    public var memoCardIDs: [String]?

    public init(id: UUID = UUID(), name: String, profileID: UUID, weekdays: [Int],
                startMinute: Int, endMinute: Int, isEnabled: Bool = true,
                todoSeriesIDs: [String]? = nil, memoCardIDs: [String]? = nil) {
        self.id = id; self.name = name; self.profileID = profileID; self.weekdays = weekdays
        self.startMinute = startMinute; self.endMinute = endMinute; self.isEnabled = isEnabled
        self.todoSeriesIDs = todoSeriesIDs; self.memoCardIDs = memoCardIDs
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !weekdays.isEmpty
        && weekdays.allSatisfy { (1...7).contains($0) }
        && (0..<1440).contains(startMinute) && (0..<1440).contains(endMinute)
        && startMinute != endMinute
    }

    public func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        matches(weekday: calendar.component(.weekday, from: date),
                minute: calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
    }

    private func matches(weekday: Int, minute: Int) -> Bool {
        guard isEnabled, isValid else { return false }
        if startMinute < endMinute {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        let previousWeekday = (weekday + 5) % 7 + 1
        return (weekdays.contains(weekday) && minute >= startMinute)
            || (weekdays.contains(previousWeekday) && minute < endMinute)
    }

    public func overlaps(_ other: Self) -> Bool {
        guard isEnabled, other.isEnabled, isValid, other.isValid else { return false }
        // A bounded week in local wall-clock minutes handles overnight and Sunday rollover.
        for day in 1...7 {
            for minute in 0..<1440 where matches(weekday: day, minute: minute)
                && other.matches(weekday: day, minute: minute) { return true }
        }
        return false
    }

    public func filteredCards(_ cards: [Card]) -> [Card] {
        cards.compactMap { card in
            if card.type == .checklist {
                guard let todoSeriesIDs else { return card }
                var copy = card
                copy.checklistItems = card.checklistItems.filter { todoSeriesIDs.contains($0.effectiveRecurrenceId) }
                copy.title = copy.checklistItems.first?.text ?? ""
                return copy.checklistItems.isEmpty ? nil : copy
            }
            if card.type == .quickNote, let memoCardIDs { return memoCardIDs.contains(card.id) ? card : nil }
            return card
        }
    }
}

public struct SmartLockScreenSchedule: Codable, Sendable {
    public static let fileName = "smart-lock-screen-v1.json"
    public static let profilesFileName = "layout-profiles-v1.json"
    public var isEnabled: Bool
    public var rules: [SmartLockScreenRule]

    public init(isEnabled: Bool = false, rules: [SmartLockScreenRule] = []) {
        self.isEnabled = isEnabled; self.rules = rules
    }

    public static func load(store: AppGroupStore) throws -> Self {
        guard let url = store.containerURL?.appendingPathComponent(fileName),
              FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    public static func profiles(store: AppGroupStore) throws -> [LayoutProfile] {
        guard let url = store.containerURL?.appendingPathComponent(profilesFileName),
              FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([LayoutProfile].self, from: Data(contentsOf: url))
    }

    public func activeRule(at date: Date, isPro: Bool, profiles: [LayoutProfile], calendar: Calendar = .current) -> SmartLockScreenRule? {
        guard isEnabled, isPro else { return nil }
        return rules.first { rule in
            rule.matches(date, calendar: calendar) && profiles.contains { $0.id == rule.profileID }
        }
    }

    /// The manual settings remain the fallback; scheduling never overwrites them or owns profile photos.
    public static func resolve(cards: [Card], settings: LockScreenSettings, store: AppGroupStore,
                               at date: Date, isPro: Bool, calendar: Calendar = .current)
    -> (cards: [Card], settings: LockScreenSettings, ruleID: UUID?) {
        let expiry = Entitlement(cachedJSON: store.defaults?.string(forKey: FlutterPreferenceKeys.purchaseState)).expirationDate
        let allowed = isPro && (expiry.map { $0 > date } ?? true)
        guard let schedule = try? load(store: store), let profiles = try? profiles(store: store),
              let rule = schedule.activeRule(at: date, isPro: allowed, profiles: profiles, calendar: calendar),
              let profile = profiles.first(where: { $0.id == rule.profileID }) else { return (cards, settings, nil) }
        return (rule.filteredCards(cards), profile.settings, rule.id)
    }

    /// Includes midnight so the weekday and content are re-evaluated even without a rule boundary.
    public func transitionDates(after now: Date, days: Int = 2, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var dates: Set<Date> = []
        for offset in 0...max(1, min(days, 8)) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if day > now { dates.insert(day) }
            guard isEnabled else { continue }
            for rule in rules where rule.isEnabled && rule.isValid {
                // Resolve wall-clock times rather than adding seconds, preserving DST behavior.
                for minute in [rule.startMinute, rule.endMinute] {
                    if let boundary = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                       boundary > now { dates.insert(boundary) }
                }
            }
        }
        return dates.sorted()
    }
}

import Foundation

/// One todo line inside a `Card`. JSON keys match the Flutter `ChecklistItem`
/// exactly so migrated payloads decode without transformation.
public struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var isDone: Bool
    public var recurrence: TodoRecurrence
    public var advancedRepeat: AdvancedRepeatRule?
    public var recurrenceId: String?
    public var recurrenceAnchorDate: Date?
    public var completedAt: Date?
    public var completedSource: String?
    public var completedDateKey: String?
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var icon: String?

    public init(
        id: String,
        text: String,
        isDone: Bool = false,
        recurrence: TodoRecurrence = .none,
        advancedRepeat: AdvancedRepeatRule? = nil,
        recurrenceId: String? = nil,
        recurrenceAnchorDate: Date? = nil,
        completedAt: Date? = nil,
        completedSource: String? = nil,
        completedDateKey: String? = nil,
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        icon: String? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.recurrence = recurrence
        self.advancedRepeat = advancedRepeat
        self.recurrenceId = recurrenceId
        self.recurrenceAnchorDate = recurrenceAnchorDate
        self.completedAt = completedAt
        self.completedSource = completedSource
        self.completedDateKey = completedDateKey
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.icon = icon
    }

    /// The recurrence series this item belongs to; falls back to its own id.
    public var effectiveRecurrenceId: String {
        recurrenceId ?? id
    }

    public var hasRecurrence: Bool { advancedRepeat != nil || recurrence != .none }

    public func isRecurrenceDue(seedDate: Date, on date: Date, calendar: Calendar = .current) -> Bool {
        if let advancedRepeat {
            return advancedRepeat.isDue(seedDate: seedDate, on: date, calendar: calendar)
        }
        return recurrence.isDue(seedDate: seedDate, on: date, calendar: calendar)
    }

    public func displayText(calendar: Calendar = .current) -> String {
        guard hasDueTime, let dueDate else { return text }
        return String(
            format: "%02d:%02d %@", calendar.component(.hour, from: dueDate),
            calendar.component(.minute, from: dueDate), text
        )
    }

    public func markingDone(
        at date: Date,
        source: String,
        calendar: Calendar = .current
    ) -> ChecklistItem {
        var copy = self
        copy.isDone = true
        copy.completedAt = date
        copy.completedSource = source
        copy.completedDateKey = FlutterDate.dateKey(date, calendar: calendar)
        return copy
    }

    public func clearingCompletion() -> ChecklistItem {
        var copy = self
        copy.isDone = false
        copy.completedAt = nil
        copy.completedSource = nil
        copy.completedDateKey = nil
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isDone, recurrence, advancedRepeat, recurrenceId, recurrenceAnchorDate
        case completedAt, completedSource, completedDateKey, dueDate, hasDueTime, icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, .id) ?? ""
        text = container.lenient(String.self, .text) ?? ""
        isDone = container.lenient(Bool.self, .isDone) ?? false
        recurrence = TodoRecurrence(fromStored: container.lenient(String.self, .recurrence))
        advancedRepeat = container.lenient(AdvancedRepeatRule.self, .advancedRepeat)
        recurrenceId = container.lenient(String.self, .recurrenceId)
        recurrenceAnchorDate = FlutterDate.parse(container.lenient(String.self, .recurrenceAnchorDate))
        completedAt = FlutterDate.parse(container.lenient(String.self, .completedAt))
        completedSource = container.lenient(String.self, .completedSource)
        completedDateKey = container.lenient(String.self, .completedDateKey)
        dueDate = FlutterDate.parse(container.lenient(String.self, .dueDate))
        hasDueTime = container.lenient(Bool.self, .hasDueTime) ?? false
        icon = container.lenient(String.self, .icon)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(isDone, forKey: .isDone)
        try container.encode(recurrence.rawValue, forKey: .recurrence)
        try container.encodeIfPresent(advancedRepeat, forKey: .advancedRepeat)
        try container.encode(recurrenceId, forKey: .recurrenceId)
        try container.encode(recurrenceAnchorDate.map(FlutterDate.localString), forKey: .recurrenceAnchorDate)
        try container.encode(completedAt.map(FlutterDate.localString), forKey: .completedAt)
        try container.encode(completedSource, forKey: .completedSource)
        try container.encode(completedDateKey, forKey: .completedDateKey)
        try container.encode(dueDate.map(FlutterDate.localString), forKey: .dueDate)
        try container.encode(hasDueTime, forKey: .hasDueTime)
        try container.encode(icon, forKey: .icon)
    }
}

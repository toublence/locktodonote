import Foundation

/// One todo line inside a `Card`. JSON keys match the Flutter `ChecklistItem`
/// exactly so migrated payloads decode without transformation.
public struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var isDone: Bool
    public var recurrence: TodoRecurrence
    public var recurrenceId: String?
    public var completedAt: Date?
    public var completedSource: String?
    public var completedDateKey: String?
    public var dueDate: Date?
    public var icon: String?

    public init(
        id: String,
        text: String,
        isDone: Bool = false,
        recurrence: TodoRecurrence = .none,
        recurrenceId: String? = nil,
        completedAt: Date? = nil,
        completedSource: String? = nil,
        completedDateKey: String? = nil,
        dueDate: Date? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.recurrence = recurrence
        self.recurrenceId = recurrenceId
        self.completedAt = completedAt
        self.completedSource = completedSource
        self.completedDateKey = completedDateKey
        self.dueDate = dueDate
        self.icon = icon
    }

    /// The recurrence series this item belongs to; falls back to its own id.
    public var effectiveRecurrenceId: String {
        recurrenceId ?? id
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
        case id, text, isDone, recurrence, recurrenceId
        case completedAt, completedSource, completedDateKey, dueDate, icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, .id) ?? ""
        text = container.lenient(String.self, .text) ?? ""
        isDone = container.lenient(Bool.self, .isDone) ?? false
        recurrence = TodoRecurrence(fromStored: container.lenient(String.self, .recurrence))
        recurrenceId = container.lenient(String.self, .recurrenceId)
        completedAt = FlutterDate.parse(container.lenient(String.self, .completedAt))
        completedSource = container.lenient(String.self, .completedSource)
        completedDateKey = container.lenient(String.self, .completedDateKey)
        dueDate = FlutterDate.parse(container.lenient(String.self, .dueDate))
        icon = container.lenient(String.self, .icon)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(isDone, forKey: .isDone)
        try container.encode(recurrence.rawValue, forKey: .recurrence)
        try container.encode(recurrenceId, forKey: .recurrenceId)
        try container.encode(completedAt.map(FlutterDate.localString), forKey: .completedAt)
        try container.encode(completedSource, forKey: .completedSource)
        try container.encode(completedDateKey, forKey: .completedDateKey)
        try container.encode(dueDate.map(FlutterDate.localString), forKey: .dueDate)
        try container.encode(icon, forKey: .icon)
    }
}

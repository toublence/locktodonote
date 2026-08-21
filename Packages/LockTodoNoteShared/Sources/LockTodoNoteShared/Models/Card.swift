import Foundation

/// A todo list, memo, or countdown. This is the single persisted entity —
/// the Flutter build stored every one of these in one JSON string under
/// `glancecard.cards.v1`, and the JSON shape is preserved here verbatim.
public struct Card: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var type: CardType
    public var privacyMode: PrivacyMode
    public var checklistItems: [ChecklistItem]
    public var isPinned: Bool
    public var showOnLockScreen: Bool
    public var targetDateTime: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastActivatedAt: Date?

    public init(
        id: String,
        title: String,
        body: String = "",
        type: CardType,
        privacyMode: PrivacyMode = .full,
        checklistItems: [ChecklistItem] = [],
        isPinned: Bool = false,
        showOnLockScreen: Bool = false,
        targetDateTime: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        lastActivatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.type = type
        self.privacyMode = privacyMode
        self.checklistItems = checklistItems
        self.isPinned = isPinned
        self.showOnLockScreen = showOnLockScreen
        self.targetDateTime = targetDateTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivatedAt = lastActivatedAt
    }

    public var doneCount: Int { checklistItems.count(where: \.isDone) }
    public var totalCount: Int { checklistItems.count }
    public var remainingCount: Int { totalCount - doneCount }

    public var nextChecklistText: String {
        checklistItems.first { !$0.isDone }?.text ?? ""
    }

    /// The day this card belongs to — its target date, or the day it was created.
    public func day(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: targetDateTime ?? createdAt)
    }

    public func dayKey(calendar: Calendar = .current) -> String {
        FlutterDate.dateKey(targetDateTime ?? createdAt, calendar: calendar)
    }

    /// Live Activities go stale about eight hours after they were started.
    public var estimatedExpirationAt: Date {
        (lastActivatedAt ?? updatedAt).addingTimeInterval(8 * 60 * 60)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, type, privacyMode, checklistItems
        case isPinned, showOnLockScreen, targetDateTime
        case createdAt, updatedAt, lastActivatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, .id) ?? ""
        title = container.lenient(String.self, .title) ?? ""
        body = container.lenient(String.self, .body) ?? ""
        type = CardType(fromStored: container.lenient(String.self, .type))
        privacyMode = PrivacyMode(fromStored: container.lenient(String.self, .privacyMode))
        checklistItems = container.lenient([ChecklistItem].self, .checklistItems) ?? []
        isPinned = container.lenient(Bool.self, .isPinned) ?? false
        showOnLockScreen = container.lenient(Bool.self, .showOnLockScreen) ?? false
        targetDateTime = FlutterDate.parse(container.lenient(String.self, .targetDateTime))
        // Dart substitutes "now" when these fail to parse; matching that keeps
        // a partially corrupt card visible instead of dropping it.
        createdAt = FlutterDate.parse(container.lenient(String.self, .createdAt)) ?? Date()
        updatedAt = FlutterDate.parse(container.lenient(String.self, .updatedAt)) ?? Date()
        lastActivatedAt = FlutterDate.parse(container.lenient(String.self, .lastActivatedAt))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(privacyMode.rawValue, forKey: .privacyMode)
        try container.encode(checklistItems, forKey: .checklistItems)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(showOnLockScreen, forKey: .showOnLockScreen)
        try container.encode(targetDateTime.map(FlutterDate.localString), forKey: .targetDateTime)
        try container.encode(FlutterDate.localString(from: createdAt), forKey: .createdAt)
        try container.encode(FlutterDate.localString(from: updatedAt), forKey: .updatedAt)
        try container.encode(lastActivatedAt.map(FlutterDate.localString), forKey: .lastActivatedAt)
    }
}

extension Card {
    /// Text shown on the Lock Screen for this card, honouring its privacy mode.
    /// The redaction strings are localized by the caller.
    public func displayText(strings: PrivacyStrings) -> String {
        switch privacyMode {
        case .titleOnly:
            return strings.checkInApp
        case .hidden:
            return strings.hiddenContent
        case .countOnly:
            switch type {
            case .checklist: return strings.remainingCount(remainingCount)
            case .countdown: return strings.timeOnly
            case .quickNote: return strings.checkInApp
            }
        case .full:
            switch type {
            case .quickNote, .countdown:
                return body
            case .checklist:
                return checklistItems
                    .filter { !$0.isDone }
                    .prefix(4)
                    .map(\.text)
                    .joined(separator: " / ")
            }
        }
    }
}

/// Localized replacements used when a card is redacted.
public struct PrivacyStrings: Sendable {
    public let checkInApp: String
    public let hiddenContent: String
    public let timeOnly: String
    public let remainingCount: @Sendable (Int) -> String

    public init(
        checkInApp: String,
        hiddenContent: String,
        timeOnly: String,
        remainingCount: @escaping @Sendable (Int) -> String
    ) {
        self.checkInApp = checkInApp
        self.hiddenContent = hiddenContent
        self.timeOnly = timeOnly
        self.remainingCount = remainingCount
    }
}

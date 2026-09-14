import Foundation

/// Mirrors `CardType` in the Flutter build. Raw values are the persisted JSON strings.
public enum CardType: String, Codable, Hashable, Sendable, CaseIterable {
    case quickNote
    case checklist
    case countdown

    public init(fromStored value: String?) {
        self = CardType(rawValue: value ?? "") ?? .quickNote
    }
}

/// Mirrors `PrivacyMode`. Controls how much of a card reaches the Lock Screen.
public enum PrivacyMode: String, Codable, Hashable, Sendable, CaseIterable {
    case full
    case titleOnly
    case hidden
    case countOnly

    public init(fromStored value: String?) {
        self = PrivacyMode(rawValue: value ?? "") ?? .full
    }
}

/// Mirrors `TodoRecurrence`.
public enum TodoRecurrence: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case daily
    case weekdays
    case weekly

    public init(fromStored value: String?) {
        self = TodoRecurrence(rawValue: value ?? "") ?? .none
    }

    /// Whether an occurrence seeded on `seedDate` is due on `date`.
    public func isDue(seedDate: Date, on date: Date, calendar: Calendar = .current) -> Bool {
        let seed = calendar.startOfDay(for: seedDate)
        let target = calendar.startOfDay(for: date)
        if target < seed { return false }
        switch self {
        case .none:
            return false
        case .daily:
            return true
        case .weekdays:
            let weekday = calendar.component(.weekday, from: target)
            return weekday >= 2 && weekday <= 6
        case .weekly:
            let days = calendar.dateComponents([.day], from: seed, to: target).day ?? 0
            return days % 7 == 0
        }
    }
}

/// The Lock Screen layouts the app can render. Raw values are the persisted
/// `lockScreenLayout` strings shared with the widget extension.
public enum LockScreenTemplate: String, Codable, Hashable, Sendable, CaseIterable {
    case calendarItems
    case memoTodo
    case dateMemo
    case dateTodo
    case imageMemo
    case imageTodo
    case ddayMemo

    public static let `default` = LockScreenTemplate.calendarItems

    /// Layouts the Live Activity renderer understands but the app never selects.
    /// The Flutter build folds them back to the default; we keep that behaviour.
    public static let unselectableLayouts: Set<String> = ["ddayTodo", "imageDday"]

    public init(fromStored value: String?) {
        guard let value, !Self.unselectableLayouts.contains(value) else {
            self = .default
            return
        }
        self = LockScreenTemplate(rawValue: value) ?? .default
    }

    public var usesTodo: Bool {
        switch self {
        case .calendarItems, .memoTodo, .dateTodo, .imageTodo: true
        case .dateMemo, .imageMemo, .ddayMemo: false
        }
    }

    public var usesMemo: Bool {
        switch self {
        case .calendarItems, .memoTodo, .dateMemo, .imageMemo: true
        case .dateTodo, .imageTodo, .ddayMemo: false
        }
    }

    public var usesImage: Bool {
        self == .imageMemo || self == .imageTodo
    }

    public var usesDday: Bool {
        self == .ddayMemo
    }

    public var requiresPro: Bool {
        proFeature != nil
    }

    public var proFeature: ProFeature? {
        switch self {
        case .memoTodo: .memoTodoTemplate
        case .dateMemo, .dateTodo: .dateTemplate
        case .imageMemo: .imageMemoTemplate
        case .imageTodo: .imageTodoTemplate
        case .ddayMemo: .ddayMemoTemplate
        case .calendarItems: nil
        }
    }
}

/// Where a Shortcuts capture lands when a template shows both todos and memos.
public enum ShortcutInsertPriority: String, Codable, Hashable, Sendable, CaseIterable {
    case todo
    case memo

    public init(fromStored value: String?) {
        self = ShortcutInsertPriority(rawValue: value ?? "") ?? .todo
    }
}

/// Mirrors `ProFeature` in the Flutter build.
public enum ProFeature: String, Hashable, Sendable, CaseIterable {
    case memoTodoTemplate
    case dateTemplate
    case imageMemoTemplate
    case imageTodoTemplate
    case ddayMemoTemplate
    case themes
    case unlimitedShortcuts
    case cardCustomization
    case displayStyle

    /// The 24-hour trial unlocks templates only — never themes or customization.
    public var unlockedByTemporaryTrial: Bool {
        switch self {
        case .memoTodoTemplate, .dateTemplate, .imageMemoTemplate, .imageTodoTemplate, .ddayMemoTemplate:
            true
        case .themes, .unlimitedShortcuts, .cardCustomization, .displayStyle:
            false
        }
    }
}

import Foundation

/// A todo completed from the Lock Screen or Dynamic Island while the app was
/// not running. The intent appends one of these; the app folds it into the
/// card store on next launch.
public struct PendingCompletedTodo: Hashable, Sendable {
    /// Composite `cardId:itemId` — the same id the dashboard exposes.
    public let id: String
    public let completedAt: Date
    public let source: String

    public init(id: String, completedAt: Date, source: String) {
        self.id = id
        self.completedAt = completedAt
        self.source = source
    }

    public init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        self.completedAt = FlutterDate.parse(dictionary["completedAt"] as? String) ?? Date()
        self.source = dictionary["source"] as? String ?? "live_activity"
    }

    public var dictionary: [String: Any] {
        [
            "id": id,
            "completedAt": FlutterDate.utcString(from: completedAt),
            "source": source,
        ]
    }

    /// Splits the composite id back into its card and item halves.
    public var components: (cardId: String, itemId: String)? {
        guard let separator = id.firstIndex(of: ":") else { return nil }
        return (String(id[id.startIndex..<separator]), String(id[id.index(after: separator)...]))
    }
}

/// Text captured through the Shortcuts intent while the app was not running.
public struct PendingQuickAdd: Hashable, Sendable {
    public let id: String
    public let text: String
    public let target: ShortcutInsertPriority
    /// `yyyy-MM-dd` key of the day the item belongs to.
    public let dateKey: String
    public let createdAt: Date

    public init(
        id: String,
        text: String,
        target: ShortcutInsertPriority,
        dateKey: String,
        createdAt: Date
    ) {
        self.id = id
        self.text = text
        self.target = target
        self.dateKey = dateKey
        self.createdAt = createdAt
    }

    public init?(dictionary: [String: Any]) {
        guard
            let id = dictionary["id"] as? String, !id.isEmpty,
            let rawText = dictionary["text"] as? String
        else { return nil }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.id = id
        self.text = text
        self.target = ShortcutInsertPriority(fromStored: dictionary["target"] as? String)
        let createdAt = FlutterDate.parse(dictionary["createdAt"] as? String) ?? Date()
        self.createdAt = createdAt
        self.dateKey = dictionary["date"] as? String ?? FlutterDate.dateKey(createdAt)
    }

    public var dictionary: [String: Any] {
        [
            "id": id,
            "text": text,
            "target": target.rawValue,
            "date": dateKey,
            "createdAt": FlutterDate.utcString(from: createdAt),
        ]
    }
}

/// A URL or text handed over by the share extension.
public struct PendingSharedLink: Hashable, Sendable {
    public let url: String?
    public let text: String?
    public let title: String
    public let createdAt: Date

    public init(url: String?, text: String?, title: String, createdAt: Date) {
        self.url = url
        self.text = text
        self.title = title
        self.createdAt = createdAt
    }

    public init?(dictionary: [String: Any]) {
        let url = dictionary["url"] as? String
        let text = dictionary["text"] as? String
        guard url != nil || text != nil else { return nil }
        self.url = url
        self.text = text
        self.title = dictionary["title"] as? String ?? ""
        if let seconds = dictionary["createdAt"] as? TimeInterval {
            self.createdAt = Date(timeIntervalSince1970: seconds)
        } else {
            self.createdAt = FlutterDate.parse(dictionary["createdAt"] as? String) ?? Date()
        }
    }
}

/// An analytics event recorded by an extension, which cannot talk to Firebase
/// directly. The app forwards these on its next foreground.
///
/// `parameters` is `Any`-valued because it round-trips through a property list.
/// Every value that reaches it has passed `PropertyListSanitizer`, so the
/// contents are immutable value types — hence the unchecked conformance.
public struct QueuedAnalyticsEvent: @unchecked Sendable {
    public let name: String
    public let parameters: [String: Any]
    public let createdAt: Date

    public init(name: String, parameters: [String: Any], createdAt: Date) {
        self.name = name
        self.parameters = parameters
        self.createdAt = createdAt
    }

    public init?(dictionary: [String: Any]) {
        guard let name = dictionary["name"] as? String, !name.isEmpty else { return nil }
        self.name = name
        self.parameters = dictionary["parameters"] as? [String: Any] ?? [:]
        let seconds = dictionary["created_at"] as? TimeInterval ?? Date().timeIntervalSince1970
        self.createdAt = Date(timeIntervalSince1970: seconds)
    }

    public var dictionary: [String: Any] {
        [
            "name": name,
            "parameters": PropertyListSanitizer.sanitize(parameters),
            "created_at": createdAt.timeIntervalSince1970,
        ]
    }

    /// Hours the event sat in the queue — Firebase stamps receipt time, not
    /// occurrence time, so this is attached as a parameter to keep the
    /// distortion measurable.
    public func queuedDelayHours(now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(createdAt) / 3600))
    }
}

/// UserDefaults rejects values that are not property-list types, and a single
/// bad value discards the whole write.
public enum PropertyListSanitizer {
    public static func sanitize(_ dictionary: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            if let sanitized = sanitize(value: value) {
                result[key] = sanitized
            }
        }
        return result
    }

    private static func sanitize(value: Any) -> Any? {
        switch value {
        case is NSNull:
            return nil
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let date as Date:
            return date
        case let data as Data:
            return data
        case let array as [Any]:
            return array.compactMap { sanitize(value: $0) }
        case let dictionary as [String: Any]:
            return sanitize(dictionary)
        default:
            return String(describing: value)
        }
    }
}

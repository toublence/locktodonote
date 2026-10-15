import Foundation

/// A value snapshot, never an EventKit object shared across executors.
public struct AppleReminderRecord: Sendable {
    public let identifier: String
    public let title: String
    public let dueDate: Date?
    public let isCompleted: Bool
    public let completionDate: Date?

    public init(identifier: String, title: String, dueDate: Date? = nil,
                isCompleted: Bool = false, completionDate: Date? = nil) {
        self.identifier = identifier
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completionDate = completionDate
    }
}

public enum AppleReminderMirror {
    private static let prefix = "apple-reminder-"

    /// URL-safe base64 keeps EventKit identifiers (including colons) out of
    /// the cardId:itemId separator used by every Lock Screen action.
    public static func cardID(for identifier: String) -> String {
        prefix + Data(identifier.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    public static func reminderID(from cardID: String) -> String? {
        guard cardID.hasPrefix(prefix) else { return nil }
        let encoded = String(cardID.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: encoded),
              let identifier = String(data: data, encoding: .utf8),
              !identifier.isEmpty else { return nil }
        return identifier
    }

    /// The caller supplies a successful, complete snapshot of selected lists.
    /// Only mirrored copies are removed; native cards and Apple data are untouched.
    public static func reconcile(
        _ records: [AppleReminderRecord], with cards: [Card],
        now: Date = Date(), calendar: Calendar = .current
    ) -> [Card] {
        let existing = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let today = calendar.startOfDay(for: now)
        var result = cards.filter { reminderID(from: $0.id) == nil }
        var seen: Set<String> = []
        for record in records where seen.insert(record.identifier).inserted {
            let id = cardID(for: record.identifier)
            let previous = existing[id]
            // Do not import years of completed history on the first connection.
            guard !record.isCompleted || previous != nil else { continue }
            let target: Date
            if record.isCompleted {
                target = previous?.targetDateTime ?? record.completionDate ?? now
            } else {
                target = max(today, calendar.startOfDay(for: record.dueDate ?? now))
            }
            var item = ChecklistItem(id: "reminder-item", text: record.title, dueDate: record.dueDate)
            if record.isCompleted {
                item = item.markingDone(
                    at: record.completionDate ?? previous?.checklistItems.first?.completedAt ?? now,
                    source: "apple_reminders", calendar: calendar
                )
                if let old = previous?.checklistItems.first, old.isDone {
                    item.completedSource = old.completedSource
                }
            }
            var card = Card(
                id: id, title: record.title, type: .checklist,
                privacyMode: previous?.privacyMode ?? .full,
                checklistItems: [item], showOnLockScreen: true,
                targetDateTime: target, createdAt: previous?.createdAt ?? now,
                updatedAt: previous?.updatedAt ?? now
            )
            if let previous, card != previous { card.updatedAt = now }
            result.append(card)
        }
        return CardMutations.sorted(result)
    }
}

public enum ReminderSyncPreferences {
    public static let enabledKey = "locktodonote.apple_reminders.enabled.v1"
    public static let calendarsKey = "locktodonote.apple_reminders.calendars.v1"
    public static let lastSyncKey = "locktodonote.apple_reminders.last_sync.v1"
}

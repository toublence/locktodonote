import Foundation
import Testing

@testable import LockTodoNoteShared

/// JSON exactly as the Flutter build writes it into `glancecard.cards.v1`:
/// explicit nulls for absent optionals and Dart's local ISO-8601 timestamps.
enum DartFixtures {
    static let checklistCard = """
    {
      "id": "1755000000000000",
      "title": "Groceries",
      "body": "",
      "type": "checklist",
      "privacyMode": "full",
      "checklistItems": [
        {
          "id": "1755000000000000-item-0",
          "text": "Milk",
          "isDone": false,
          "recurrence": "none",
          "recurrenceId": null,
          "completedAt": null,
          "completedSource": null,
          "completedDateKey": null,
          "dueDate": null,
          "icon": null
        },
        {
          "id": "1755000000000000-item-1",
          "text": "Eggs",
          "isDone": true,
          "recurrence": "daily",
          "recurrenceId": "series-1",
          "completedAt": "2026-08-21T10:15:00.000000",
          "completedSource": "live_activity",
          "completedDateKey": "2026-08-21",
          "dueDate": null,
          "icon": null
        }
      ],
      "isPinned": false,
      "showOnLockScreen": true,
      "targetDateTime": "2026-08-21T00:00:00.000",
      "createdAt": "2026-08-21T09:42:13.123456",
      "updatedAt": "2026-08-21T09:42:13.123456",
      "lastActivatedAt": null
    }
    """

    static let memoCard = """
    {
      "id": "1755000000000001",
      "title": "Remember",
      "body": "Call the clinic\\nAsk about results",
      "type": "quickNote",
      "privacyMode": "titleOnly",
      "checklistItems": [],
      "isPinned": true,
      "showOnLockScreen": true,
      "targetDateTime": null,
      "createdAt": "2026-08-20T18:00:00.000000",
      "updatedAt": "2026-08-20T18:30:00.000000",
      "lastActivatedAt": "2026-08-20T18:31:00.000000"
    }
    """
}

@Suite("Card decoding from Flutter JSON")
struct CardCodingTests {
    private func decode(_ json: String) throws -> Card {
        try JSONDecoder().decode(Card.self, from: Data(json.utf8))
    }

    @Test func decodesChecklistCard() throws {
        let card = try decode(DartFixtures.checklistCard)
        #expect(card.id == "1755000000000000")
        #expect(card.title == "Groceries")
        #expect(card.type == .checklist)
        #expect(card.privacyMode == .full)
        #expect(card.checklistItems.count == 2)
        #expect(card.showOnLockScreen)
        #expect(!card.isPinned)
        #expect(card.doneCount == 1)
        #expect(card.remainingCount == 1)
        #expect(card.targetDateTime != nil)
        #expect(card.lastActivatedAt == nil)
    }

    @Test func decodesChecklistItemDetail() throws {
        let card = try decode(DartFixtures.checklistCard)
        let recurring = card.checklistItems[1]
        #expect(recurring.recurrence == .daily)
        #expect(recurring.recurrenceId == "series-1")
        #expect(recurring.effectiveRecurrenceId == "series-1")
        #expect(recurring.completedSource == "live_activity")
        #expect(recurring.completedDateKey == "2026-08-21")
        #expect(recurring.completedAt != nil)

        let plain = card.checklistItems[0]
        #expect(plain.recurrence == .none)
        #expect(plain.effectiveRecurrenceId == "1755000000000000-item-0")
    }

    @Test func decodesMemoCard() throws {
        let card = try decode(DartFixtures.memoCard)
        #expect(card.type == .quickNote)
        #expect(card.privacyMode == .titleOnly)
        #expect(card.isPinned)
        #expect(card.body.contains("Call the clinic"))
        #expect(card.totalCount == 0)
        #expect(card.lastActivatedAt != nil)
    }

    @Test func roundTripsWithoutLosingFields() throws {
        let original = try decode(DartFixtures.checklistCard)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Card.self, from: data)
        #expect(restored.id == original.id)
        #expect(restored.checklistItems == original.checklistItems)
        #expect(restored.type == original.type)
        #expect(restored.privacyMode == original.privacyMode)
        #expect(abs(restored.createdAt.timeIntervalSince(original.createdAt)) < 0.000_002)
    }

    /// One bad field must not take the whole card down — Dart fell back to
    /// defaults, and a dropped card is data loss during migration.
    @Test func survivesUnexpectedFieldTypes() throws {
        let json = """
        {
          "id": "abc",
          "title": 42,
          "type": "not-a-type",
          "privacyMode": null,
          "checklistItems": [],
          "isPinned": "yes",
          "createdAt": "garbage",
          "updatedAt": "2026-08-21T09:42:13.123456"
        }
        """
        let card = try decode(json)
        #expect(card.id == "abc")
        #expect(card.title == "")
        #expect(card.type == .quickNote, "unknown type falls back like Dart's firstWhere orElse")
        #expect(card.privacyMode == .full)
        #expect(!card.isPinned)
    }

    @Test func decodesFullCardArray() throws {
        let json = "[\(DartFixtures.checklistCard),\(DartFixtures.memoCard)]"
        let cards = try JSONDecoder().decode([Card].self, from: Data(json.utf8))
        #expect(cards.count == 2)
    }

    @Test func computesDayKeyFromTargetDateThenCreatedAt() throws {
        let withTarget = try decode(DartFixtures.checklistCard)
        #expect(withTarget.dayKey() == "2026-08-21")

        let withoutTarget = try decode(DartFixtures.memoCard)
        #expect(withoutTarget.dayKey() == "2026-08-20", "falls back to createdAt")
    }
}

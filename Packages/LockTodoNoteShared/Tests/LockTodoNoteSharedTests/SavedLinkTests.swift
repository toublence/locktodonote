import Foundation
import Testing

@testable import LockTodoNoteShared

@Suite("Saved links")
struct SavedLinkTests {
    /// The shape the Flutter build wrote into `glancecard.links.v1`.
    private let flutterJSON = """
    [{
      "id": "1755000000000000",
      "url": "https://www.example.com/article",
      "title": "An article",
      "thumbnailUrl": null,
      "siteName": "Example",
      "categoryId": "read_later",
      "createdAt": "2026-08-20T18:00:00.000000",
      "updatedAt": "2026-08-20T18:00:00.000000"
    }]
    """

    @Test func decodesFlutterLinks() throws {
        let links = try JSONDecoder().decode([SavedLink].self, from: Data(flutterJSON.utf8))
        let link = try #require(links.first)
        #expect(link.id == "1755000000000000")
        #expect(link.title == "An article")
        #expect(link.categoryId == "read_later")
        #expect(link.siteName == "Example")
        #expect(!link.isTextOnly)
    }

    @Test func stripsWWWFromTheDisplayedDomain() throws {
        let links = try JSONDecoder().decode([SavedLink].self, from: Data(flutterJSON.utf8))
        #expect(links.first?.domain == "example.com")
    }

    @Test func roundTripsWithoutLoss() throws {
        let original = try JSONDecoder().decode([SavedLink].self, from: Data(flutterJSON.utf8))
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode([SavedLink].self, from: data)
        #expect(restored == original)
    }

    @Test func buildsFromASharedURL() {
        let now = FlutterDate.parse("2026-08-21T09:00:00.000000")!
        let pending = PendingSharedLink(
            url: "https://example.com/post",
            text: nil,
            title: "A post",
            createdAt: now
        )
        let link = SavedLink(pending: pending)
        #expect(link.url == "https://example.com/post")
        #expect(link.title == "A post")
        #expect(!link.isTextOnly)
        #expect(link.destination != nil)
    }

    /// Shared plain text has no URL; it is still worth keeping, just not tappable.
    @Test func buildsFromSharedTextWithoutAURL() {
        let pending = PendingSharedLink(url: nil, text: "Remember this", title: "", createdAt: Date())
        let link = SavedLink(pending: pending)
        #expect(link.isTextOnly)
        #expect(link.title == "Remember this")
        #expect(link.destination == nil)
        #expect(link.domain.isEmpty)
    }

    @Test func fallsBackToTheTextWhenNoTitleWasShared() {
        let pending = PendingSharedLink(
            url: "https://example.com",
            text: nil,
            title: "   ",
            createdAt: Date()
        )
        #expect(SavedLink(pending: pending).title == "https://example.com")
    }

    @Test func ignoresAShareWithNeitherURLNorText() {
        #expect(PendingSharedLink(dictionary: ["title": "nothing"]) == nil)
    }

    @Test func readsBothTimestampFormatsTheExtensionsProduce() throws {
        // The share extension writes epoch seconds; other queues write ISO text.
        let epoch = try #require(
            PendingSharedLink(dictionary: ["url": "https://a.example", "createdAt": 1_787_000_000.0])
        )
        #expect(epoch.createdAt.timeIntervalSince1970 == 1_787_000_000)

        let iso = try #require(
            PendingSharedLink(dictionary: [
                "url": "https://b.example",
                "createdAt": "2026-08-21T09:00:00.000000Z",
            ])
        )
        #expect(FlutterDate.dateKey(iso.createdAt, calendar: {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar
        }()) == "2026-08-21")
    }
}

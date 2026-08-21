import Foundation
import Testing

@testable import LockTodoNoteShared

@Suite("Flutter date compatibility")
struct FlutterDateTests {
    /// The exact shape `DateTime.now().toIso8601String()` produces: microsecond
    /// precision and no zone designator, which `ISO8601DateFormatter` rejects.
    @Test func parsesLocalTimestampWithMicroseconds() throws {
        let date = try #require(FlutterDate.parse("2026-08-21T09:42:13.123456"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 21)
        #expect(parts.hour == 9)
        #expect(parts.minute == 42)
        #expect(parts.second == 13)
    }

    @Test func parsesUTCTimestamp() throws {
        let date = try #require(FlutterDate.parse("2026-08-21T00:42:13.123456Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        #expect(parts.hour == 0)
        #expect(parts.minute == 42)
    }

    @Test func treatsMissingZoneAsLocal() throws {
        let local = try #require(FlutterDate.parse("2026-08-21T09:42:13.000000"))
        let utc = try #require(FlutterDate.parse("2026-08-21T09:42:13.000000Z"))
        let offset = TimeZone.current.secondsFromGMT(for: local)
        #expect(abs(utc.timeIntervalSince(local) - Double(offset)) < 1)
    }

    @Test(arguments: [
        "2026-08-21T09:42:13.123456",
        "2026-08-21T09:42:13.123",
        "2026-08-21T09:42:13",
        "2026-08-21T09:42",
        "2026-08-21 09:42:13.123456",
        "2026-08-21",
        "2026-08-21T09:42:13.123456+09:00",
        "2026-08-21T09:42:13.123456-0500",
    ])
    func parsesEveryShapeDartCanEmit(_ raw: String) {
        #expect(FlutterDate.parse(raw) != nil, "should parse \(raw)")
    }

    @Test(arguments: ["", "   ", "not-a-date", "2026/08/21", "20260821"])
    func rejectsMalformedInput(_ raw: String) {
        #expect(FlutterDate.parse(raw) == nil)
    }

    @Test func handlesNil() {
        #expect(FlutterDate.parse(nil) == nil)
    }

    @Test func roundTripsThroughLocalString() throws {
        let original = try #require(FlutterDate.parse("2026-08-21T09:42:13.123456"))
        let encoded = FlutterDate.localString(from: original)
        let decoded = try #require(FlutterDate.parse(encoded))
        #expect(abs(decoded.timeIntervalSince(original)) < 0.000_002)
    }

    @Test func localStringMatchesDartFormat() throws {
        let date = try #require(FlutterDate.parse("2026-08-21T09:42:13.123456"))
        let encoded = FlutterDate.localString(from: date)
        #expect(encoded.hasPrefix("2026-08-21T09:42:13."))
        #expect(encoded.count == 26, "yyyy-MM-ddTHH:mm:ss.ssssss is 26 characters")
    }

    @Test func buildsAndReadsDateKeys() throws {
        let date = try #require(FlutterDate.parse("2026-08-21T23:59:59.999999"))
        #expect(FlutterDate.dateKey(date) == "2026-08-21")

        let fromKey = try #require(FlutterDate.date(fromKey: "2026-08-21"))
        #expect(FlutterDate.dateKey(fromKey) == "2026-08-21")

        // Intents sometimes hand back a full timestamp where a key is expected.
        let fromTimestamp = try #require(FlutterDate.date(fromKey: "2026-08-21T09:42:13.123456"))
        #expect(FlutterDate.dateKey(fromTimestamp) == "2026-08-21")
    }
}

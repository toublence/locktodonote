import Foundation

/// Reads and writes the date strings produced by the Flutter build.
///
/// `DateTime.toIso8601String()` emits microsecond precision and omits the zone
/// designator for local times (`2026-08-21T09:42:00.123456`), which
/// `ISO8601DateFormatter` rejects. Dart's own `DateTime.parse` is lenient:
/// a missing zone means local time, the separator may be `T` or a space, and
/// the time part is optional. This mirrors that behaviour so migrated data
/// keeps the exact instants the user saw in the Flutter app.
public enum FlutterDate {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?\s*(Z|z|[+-]\d{2}:?\d{2})?)?$"#
    )

    public static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = pattern.firstMatch(in: text, range: range) else { return nil }

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        guard
            let year = group(1).flatMap(Int.init),
            let month = group(2).flatMap(Int.init),
            let day = group(3).flatMap(Int.init)
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = group(4).flatMap(Int.init) ?? 0
        components.minute = group(5).flatMap(Int.init) ?? 0
        components.second = group(6).flatMap(Int.init) ?? 0

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(for: group(8))
        guard let base = calendar.date(from: components) else { return nil }

        // Dart keeps microseconds; Date holds them as a fractional offset.
        guard let fraction = group(7), !fraction.isEmpty else { return base }
        let digits = fraction.prefix(6)
        let padded = digits + String(repeating: "0", count: 6 - digits.count)
        guard let microseconds = Int(padded) else { return base }
        return base.addingTimeInterval(Double(microseconds) / 1_000_000)
    }

    private static func timeZone(for designator: String?) -> TimeZone {
        guard let designator, !designator.isEmpty else { return .current }
        if designator == "Z" || designator == "z" { return TimeZone(secondsFromGMT: 0)! }
        let normalized = designator.replacingOccurrences(of: ":", with: "")
        guard normalized.count == 5,
              let hours = Int(normalized.dropFirst().prefix(2)),
              let minutes = Int(normalized.suffix(2))
        else { return .current }
        let magnitude = hours * 3600 + minutes * 60
        let seconds = normalized.hasPrefix("-") ? -magnitude : magnitude
        return TimeZone(secondsFromGMT: seconds) ?? .current
    }

    /// Local-time representation matching `DateTime.toIso8601String()`.
    public static func localString(from date: Date) -> String {
        string(from: date, timeZone: .current, suffix: "")
    }

    /// UTC representation matching `DateTime.toUtc().toIso8601String()`.
    public static func utcString(from date: Date) -> String {
        string(from: date, timeZone: TimeZone(secondsFromGMT: 0)!, suffix: "Z")
    }

    private static func string(from date: Date, timeZone: TimeZone, suffix: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let microseconds = (parts.nanosecond ?? 0) / 1000
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%06d%@",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
            microseconds, suffix
        )
    }

    /// `yyyy-MM-dd` in the user's calendar — the id shared with widgets and intents.
    public static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Parses a `yyyy-MM-dd` key, tolerating a full timestamp by using its date part.
    public static func date(fromKey key: String?, calendar: Calendar = .current) -> Date? {
        guard let key, key.count >= 10 else { return nil }
        guard let parsed = parse(String(key.prefix(10))) else { return nil }
        return calendar.startOfDay(for: parsed)
    }
}

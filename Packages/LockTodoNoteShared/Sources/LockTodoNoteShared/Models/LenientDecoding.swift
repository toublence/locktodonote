import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value, treating both "absent" and "wrong type" as absent.
    ///
    /// Dart's `fromJson` constructors fall back to a default on any bad field
    /// rather than discarding the whole record. Matching that keeps one
    /// malformed value from making a user's card disappear during migration.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

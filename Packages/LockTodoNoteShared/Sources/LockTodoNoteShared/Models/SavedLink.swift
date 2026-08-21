import Foundation

/// A link or snippet captured through the share sheet.
///
/// JSON keys match the Flutter `SavedLink` so the migrated
/// `glancecard.links.v1` payload decodes unchanged.
public struct SavedLink: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var url: String
    public var title: String
    public var thumbnailUrl: String?
    public var siteName: String?
    /// Retained from the Flutter categories so existing data survives, even
    /// though the SwiftUI list is currently flat.
    public var categoryId: String
    public var createdAt: Date
    public var updatedAt: Date

    public static let defaultCategoryId = "read_later"

    public init(
        id: String,
        url: String,
        title: String,
        thumbnailUrl: String? = nil,
        siteName: String? = nil,
        categoryId: String = SavedLink.defaultCategoryId,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.thumbnailUrl = thumbnailUrl
        self.siteName = siteName
        self.categoryId = categoryId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Host without a `www.` prefix — what the row shows under the title.
    public var domain: String {
        guard let host = URLComponents(string: url)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Shared plain text is stored with an empty `url`.
    public var isTextOnly: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var destination: URL? {
        isTextOnly ? nil : URL(string: url)
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, title, thumbnailUrl, siteName, categoryId, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, .id) ?? ""
        url = container.lenient(String.self, .url) ?? ""
        title = container.lenient(String.self, .title) ?? ""
        thumbnailUrl = container.lenient(String.self, .thumbnailUrl)
        siteName = container.lenient(String.self, .siteName)
        categoryId = container.lenient(String.self, .categoryId) ?? Self.defaultCategoryId
        createdAt = FlutterDate.parse(container.lenient(String.self, .createdAt)) ?? Date()
        updatedAt = FlutterDate.parse(container.lenient(String.self, .updatedAt)) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encode(siteName, forKey: .siteName)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(FlutterDate.localString(from: createdAt), forKey: .createdAt)
        try container.encode(FlutterDate.localString(from: updatedAt), forKey: .updatedAt)
    }

    /// Builds a link from a share-extension capture.
    public init(pending: PendingSharedLink) {
        let now = pending.createdAt
        let url = pending.url ?? ""
        let fallbackTitle = pending.text ?? url
        let trimmedTitle = pending.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: "share-\(Int(now.timeIntervalSince1970 * 1_000_000))",
            url: url,
            title: trimmedTitle.isEmpty ? String(fallbackTitle.prefix(80)) : trimmedTitle,
            createdAt: now,
            updatedAt: now
        )
    }
}

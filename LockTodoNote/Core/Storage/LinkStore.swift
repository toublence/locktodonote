import Foundation
import LockTodoNoteShared

/// Holds links captured through the share sheet.
///
/// The share extension can only write to a queue in the App Group; this drains
/// that queue on every foreground and folds it into the stored list. Without a
/// consumer the queue would grow without bound.
@MainActor
final class LinkStore: ObservableObject {
    @Published private(set) var links: [SavedLink] = []

    private let store: AppGroupStore
    private let defaults: UserDefaults?

    init(store: AppGroupStore = AppGroupStore()) {
        self.store = store
        self.defaults = store.defaults
        load()
    }

    /// Reads the stored list, then absorbs anything the extension queued.
    func load() {
        var current = decodeStored()
        let pending = store.drainPendingSharedLinks()
        guard !pending.isEmpty else {
            links = sorted(current)
            return
        }
        // Same URL captured twice is the same item, not two.
        var seenURLs = Set(current.filter { !$0.isTextOnly }.map(\.url))
        for item in pending {
            let link = SavedLink(pending: item)
            if !link.isTextOnly {
                guard seenURLs.insert(link.url).inserted else { continue }
            }
            current.append(link)
        }
        links = sorted(current)
        persist()
    }

    func delete(id: String) {
        links.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        links = []
        persist()
    }

    private func sorted(_ items: [SavedLink]) -> [SavedLink] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    /// Stored under the Flutter key so migrated links appear untouched.
    private func decodeStored() -> [SavedLink] {
        guard
            let raw = defaults?.string(forKey: FlutterPreferenceKeys.links),
            let data = raw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([SavedLink].self, from: data)
        else { return [] }
        return decoded
    }

    private func persist() {
        guard let defaults else { return }
        guard
            let data = try? JSONEncoder().encode(links),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(raw, forKey: FlutterPreferenceKeys.links)
    }
}

import Foundation
import LockTodoNoteShared
import SwiftUI

/// Local snapshots reference the same todos/memos; photos get independent copies.
@MainActor
final class LayoutProfileStore: ObservableObject {
    @Published private(set) var profiles: [LayoutProfile] = []
    @Published private(set) var loadFailed = false
    var onChange: (() -> Void)?
    private let store: AppGroupStore
    private var fileURL: URL? { store.containerURL?.appendingPathComponent("layout-profiles-v1.json") }

    init(store: AppGroupStore) {
        self.store = store
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            profiles = try JSONDecoder().decode([LayoutProfile].self, from: Data(contentsOf: fileURL))
        } catch {
            // Never overwrite an unreadable collection with an empty array.
            loadFailed = true
        }
    }

    enum ProfileError: LocalizedError {
        case unavailable, unreadable, invalidName, freeLimit, missingImage, scheduled
        var errorDescription: String? {
            switch self {
            case .unavailable, .unreadable:
                bilingualString(korean: "구성을 저장할 수 없습니다. 기존 데이터는 유지됩니다.", english: "Layouts could not be saved. Your existing data is preserved.")
            case .invalidName:
                bilingualString(korean: "구성 이름을 입력하세요.", english: "Enter a layout name.")
            case .freeLimit:
                bilingualString(korean: "여러 구성 저장은 Pro에서 사용할 수 있습니다.", english: "Multiple saved layouts require Pro.")
            case .scheduled:
                bilingualString(korean: "이 구성을 사용하는 전환 규칙을 먼저 삭제하세요.", english: "Remove the switching rules that use this layout first.")
            case .missingImage:
                bilingualString(korean: "구성의 사진을 읽을 수 없습니다. 사진을 다시 선택하세요.", english: "The layout photo could not be read. Please select it again.")
            }
        }
    }

    func save(name: String, settings: LockScreenSettings, colorTheme: String, isPro: Bool, replacing id: UUID? = nil) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileError.invalidName }
        guard !loadFailed else { throw ProfileError.unreadable }
        let existing = id.flatMap { key in profiles.first { $0.id == key } }
        guard isPro || profiles.isEmpty || (existing != nil && existing?.id == profiles.first?.id) else { throw ProfileError.freeLimit }
        var createdFiles: [String] = []
        do {
            let snapshot = try copyImages(in: settings, createdFiles: &createdFiles)
            let profile = LayoutProfile(id: existing?.id ?? UUID(), name: String(name.prefix(80)), settings: snapshot, colorTheme: colorTheme)
            var updated = profiles
            if let index = updated.firstIndex(where: { $0.id == profile.id }) {
                updated[index] = profile
            } else {
                updated.append(profile)
            }
            try persist(updated)
            if let existing { removeImages(in: existing.settings) }
        } catch {
            createdFiles.forEach { store.removeLockScreenImage(fileName: $0) }
            throw error
        }
    }

    func remove(_ profile: LayoutProfile) throws {
        let schedule = try SmartLockScreenSchedule.load(store: store)
        guard !schedule.rules.contains(where: { $0.profileID == profile.id }) else { throw ProfileError.scheduled }
        try persist(profiles.filter { $0.id != profile.id })
        removeImages(in: profile.settings)
    }

    func settingsForApplication(_ profile: LayoutProfile) throws -> LockScreenSettings {
        var createdFiles: [String] = []
        do {
            // Active settings must not own a saved profile's files: changing a photo
            // removes its previous active file in the existing image store.
            return try copyImages(in: profile.settings, createdFiles: &createdFiles)
        } catch {
            createdFiles.forEach { store.removeLockScreenImage(fileName: $0) }
            throw error
        }
    }

    private func persist(_ updated: [LayoutProfile]) throws {
        guard !loadFailed else { throw ProfileError.unreadable }
        guard let fileURL else { throw ProfileError.unavailable }
        let data = try JSONEncoder().encode(updated)
        try data.write(to: fileURL, options: .atomic)
        store.relaxFileProtection(at: fileURL)
        profiles = updated
        onChange?()
    }

    private func copyImages(in settings: LockScreenSettings, createdFiles: inout [String]) throws -> LockScreenSettings {
        var snapshot = settings
        var copies: [String: String] = [:]
        for source in Set([settings.imageFileName, settings.imageMemoFileName, settings.imageTodoFileName].compactMap { $0 }) {
            let data: Data
            if let url = store.lockScreenImageURL(fileName: source), FileManager.default.fileExists(atPath: url.path) {
                data = try Data(contentsOf: url)
            } else if let thumbnail = store.lockScreenImageData(fileName: source) {
                data = thumbnail
            } else {
                throw ProfileError.missingImage
            }
            let destination = try LockScreenImageStore(store: store).save(imageData: data, replacing: nil)
            createdFiles.append(destination)
            copies[source] = destination
        }
        snapshot.imageFileName = settings.imageFileName.flatMap { copies[$0] }
        snapshot.imageMemoFileName = settings.imageMemoFileName.flatMap { copies[$0] }
        snapshot.imageTodoFileName = settings.imageTodoFileName.flatMap { copies[$0] }
        return snapshot
    }

    private func removeImages(in settings: LockScreenSettings) {
        Set([settings.imageFileName, settings.imageMemoFileName, settings.imageTodoFileName].compactMap { $0 })
            .forEach { store.removeLockScreenImage(fileName: $0) }
    }
}

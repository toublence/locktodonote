import Foundation
import UIKit
import LockTodoNoteShared

/// Stores the picked photo where the Live Activity and widget can read it.
///
/// Two copies are kept on purpose: the full file in the App Group container,
/// and a 96×84 JPEG in shared defaults. An activity payload is capped at a few
/// kilobytes, so the thumbnail is the only version the Lock Screen can afford.
struct LockScreenImageStore {
    let store: AppGroupStore

    init(store: AppGroupStore = AppGroupStore()) {
        self.store = store
    }

    private static let thumbnailSize = CGSize(width: 96, height: 84)
    /// Full-size cap: large enough for the widget, small enough to stay cheap.
    private static let maxDimension: CGFloat = 1024

    enum ImageStoreError: LocalizedError {
        case noContainer
        case unreadableImage

        var errorDescription: String? {
            switch self {
            case .noContainer:
                appString(localized: "image.noContainer",
                    defaultValue: "Shared storage is unavailable."
                )
            case .unreadableImage:
                appString(localized: "image.unreadable",
                    defaultValue: "That photo could not be read."
                )
            }
        }
    }

    /// Writes a new image and removes the one it replaces.
    @discardableResult
    func save(imageData: Data, replacing previousFileName: String?) throws -> String {
        guard let directory = store.lockScreenImageDirectory else { throw ImageStoreError.noContainer }
        guard let image = UIImage(data: imageData) else { throw ImageStoreError.unreadableImage }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store.relaxFileProtection(at: directory)

        if let previousFileName, !previousFileName.isEmpty {
            store.removeLockScreenImage(fileName: previousFileName)
        }

        // The Flutter build used this prefix; kept so old and new files sit
        // together in one recognisable place.
        let fileName = "lockday-\(UUID().uuidString).png"
        let url = directory.appendingPathComponent(fileName)
        let resized = Self.resized(image, maxDimension: Self.maxDimension)
        guard let data = resized.pngData() else { throw ImageStoreError.unreadableImage }
        try data.write(to: url, options: .atomic)
        store.relaxFileProtection(at: url)

        if let thumbnail = Self.thumbnailData(from: image) {
            store.saveLockScreenImageData(thumbnail, fileName: fileName)
        }
        return fileName
    }

    func remove(fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        store.removeLockScreenImage(fileName: fileName)
    }

    func image(fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        if let data = store.lockScreenImageData(fileName: fileName), let image = UIImage(data: data) {
            return image
        }
        guard let url = store.lockScreenImageURL(fileName: fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Scaling

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Centre-cropped fill, matching what the Live Activity column expects.
    private static func thumbnailData(from image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let target = thumbnailSize
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: (target.width - drawSize.width) / 2,
            y: (target.height - drawSize.height) / 2
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).jpegData(withCompressionQuality: 0.82) { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

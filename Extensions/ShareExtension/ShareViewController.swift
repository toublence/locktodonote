import MobileCoreServices
import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
  private let appGroupId = "group.com.namslab.glancecard"
  private let pendingSharedLinksKey = "pending_shared_links"

  override func isContentValid() -> Bool {
    true
  }

  override func didSelectPost() {
    Task {
      await saveSharedItems()
      extensionContext?.completeRequest(returningItems: nil)
    }
  }

  override func configurationItems() -> [Any]! {
    []
  }

  private func saveSharedItems() async {
    guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
      return
    }

    for item in extensionItems {
      let title = item.attributedTitle?.string ?? item.attributedContentText?.string
      for provider in item.attachments ?? [] {
        if let payload = await payload(from: provider, title: title) {
          append(payload)
        }
      }
    }
  }

  private func payload(from provider: NSItemProvider, title: String?) async -> [String: Any]? {
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
       let url = await loadUrl(from: provider) {
      return [
        "url": url.absoluteString,
        "title": title ?? "",
        "createdAt": Date().timeIntervalSince1970,
      ]
    }

    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
       let text = await loadText(from: provider) {
      return [
        "text": text,
        "title": title ?? "",
        "createdAt": Date().timeIntervalSince1970,
      ]
    }

    return nil
  }

  private func loadUrl(from provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
        if let url = item as? URL {
          continuation.resume(returning: url)
        } else if let string = item as? String {
          continuation.resume(returning: URL(string: string))
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  private func loadText(from provider: NSItemProvider) async -> String? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
        if let text = item as? String {
          continuation.resume(returning: text)
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  private func append(_ payload: [String: Any]) {
    guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
    var links = defaults.array(forKey: pendingSharedLinksKey) as? [[String: Any]] ?? []
    links.append(payload)
    defaults.set(links, forKey: pendingSharedLinksKey)
    defaults.synchronize()
  }
}

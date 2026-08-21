import Foundation
import LockTodoNoteShared

/// Destinations reachable from the Lock Screen, the widget, and Shortcuts.
///
/// The scheme and hosts are hardcoded into the shipped Live Activity views, so
/// they are part of the app's public contract and cannot be renamed.
enum DeepLink: Equatable {
    case quickMemo(source: String?)
    case quickTodo(source: String?)
    case dashboard(source: String?)
    case card(id: String)

    init?(url: URL) {
        guard url.scheme == AppGroupKeys.urlScheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let source = components?.queryItems?.first { $0.name == "source" }?.value

        switch url.host {
        case "quick-memo":
            self = .quickMemo(source: source)
        case "quick-todo":
            self = .quickTodo(source: source)
        case "dashboard":
            self = .dashboard(source: source)
        case "cards":
            let id = url.pathComponents.first { $0 != "/" } ?? ""
            guard !id.isEmpty else { return nil }
            self = .card(id: id)
        default:
            return nil
        }
    }

    /// How the app was entered, for the open-source analytics event.
    var source: String? {
        switch self {
        case .quickMemo(let source), .quickTodo(let source), .dashboard(let source):
            source
        case .card:
            "live_activity"
        }
    }
}

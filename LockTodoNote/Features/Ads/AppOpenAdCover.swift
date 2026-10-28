import UIKit

/// A window above the app that hosts the app open ad.
///
/// Presenting from the app's own window collides with whatever SwiftUI is
/// presenting there (a sheet, an alert, onboarding), and an ad that fails to
/// present is an ad that was never shown. This window always has a free root
/// view controller. While an ad is still loading it also stands in for the
/// launch screen, so the app cannot be used underneath an incoming ad.
@MainActor
final class AppOpenAdCover {
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?

    var hostViewController: UIViewController? { window?.rootViewController }

    /// `waiting` shows the launch background with a spinner; otherwise the
    /// cover is clear because an ad is about to present over it. Returns false
    /// when no scene is in the foreground to cover.
    @discardableResult
    func show(waiting: Bool) -> Bool {
        if window != nil {
            setWaiting(waiting)
            return true
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
        else { return false }
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        // The keyboard lives in a system window above every app window.
        scene.windows.forEach { $0.endEditing(true) }
        let controller = CoverViewController()
        controller.isWaiting = waiting
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func setWaiting(_ waiting: Bool) {
        (window?.rootViewController as? CoverViewController)?.isWaiting = waiting
    }

    func hide() {
        guard let window else { return }
        window.isHidden = true
        self.window = nil
        let restored = previousKeyWindow
            ?? window.windowScene?.windows.first { $0.windowLevel == .normal }
        restored?.makeKey()
        previousKeyWindow = nil
    }
}

private final class CoverViewController: UIViewController {
    var isWaiting = true {
        didSet { if isViewLoaded { applyState() } }
    }
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        applyState()
    }

    private func applyState() {
        // Matches UILaunchScreen, so a cold launch reads as one launch screen.
        view.backgroundColor = isWaiting ? UIColor(named: "LaunchBackground") ?? .systemBackground : .clear
        if isWaiting { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
import FirebaseCore
#endif

/// Configures Firebase before anything else touches it.
///
/// This must run from the app's entry point, not from a `@StateObject`: SwiftUI
/// defers those until the first view is built, and Crashlytics starts up before
/// that. Configuring late produced a real "default Firebase app has not yet
/// been configured" error at launch, and any event logged in that window was
/// dropped.
enum FirebaseBootstrap {
    /// Asked of Firebase directly rather than cached, which keeps this free of
    /// shared mutable state under strict concurrency.
    static var isConfigured: Bool {
        #if canImport(FirebaseAnalytics)
        FirebaseApp.app() != nil
        #else
        false
        #endif
    }

    static func configure() {
        #if canImport(FirebaseAnalytics)
        guard FirebaseApp.app() == nil else { return }
        // The bundled GoogleService-Info.plist is registered to a different
        // bundle id than this app, so Firebase logs a mismatch warning. That is
        // deliberate: it keeps events flowing into the same app record the
        // Flutter build used, which is what preserves the existing dashboards.
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        #endif
    }
}

/// Firebase adapter.
///
/// Compiled conditionally so the app still builds if the SDK is ever removed.
/// The existing Firebase project and `GoogleService-Info.plist` are reused
/// unchanged to keep the historical dashboards continuous.
final class FirebaseAnalyticsBackend: AnalyticsBackend {
    var isEnabled: Bool { FirebaseBootstrap.isConfigured }

    init() {
        // Safety net: if the entry point ever stops calling this, configure
        // here rather than silently reporting nothing.
        FirebaseBootstrap.configure()
    }

    func log(name: String, parameters: [String: Any]) {
        #if canImport(FirebaseAnalytics)
        guard isEnabled else { return }
        Analytics.logEvent(name, parameters: parameters)
        #endif
    }
}

/// Collects events in memory. Used by tests to assert on names and parameters.
final class RecordingAnalyticsBackend: AnalyticsBackend {
    struct Event {
        let name: String
        let parameters: [String: Any]
    }

    private(set) var events: [Event] = []
    var isEnabled: Bool { true }

    func log(name: String, parameters: [String: Any]) {
        events.append(Event(name: name, parameters: parameters))
    }

    func names() -> [String] { events.map(\.name) }

    func parameters(for name: String) -> [String: Any]? {
        events.last { $0.name == name }?.parameters
    }
}

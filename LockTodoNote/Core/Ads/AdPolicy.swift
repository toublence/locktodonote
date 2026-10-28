import Foundation

/// The app shows one ad format only: an app open ad when the app launches or
/// returns from the background.
enum AdPolicy {
    static let productionAppOpenUnitID = "ca-app-pub-6169297934919363/1667809967"
    #if DEBUG
    static let isTest = true
    /// Google's official app open test unit keeps development traffic out of production.
    static let appOpenUnitID = "ca-app-pub-3940256099942544/5575463023"
    #else
    static let isTest = false
    static let appOpenUnitID = productionAppOpenUnitID
    #endif
    static let placement = "app_open"

    /// Minimum gap between two app open ads. Persisted, so a relaunch does not reset it.
    static let appOpenCooldown: TimeInterval = 2 * 60
    /// Google invalidates a loaded app open ad after four hours.
    static let appOpenLifetime: TimeInterval = 4 * 60 * 60
    /// How long the launch cover waits for an ad that is still loading before
    /// revealing the app. An ad must never appear after the user has started
    /// interacting, so a late ad is kept for the next app open instead. A cold
    /// launch measured about 4s from cover to impression on the simulator,
    /// most of it the SDK's own WebKit start-up.
    static let appOpenMaxWait: TimeInterval = 8

    static var isEnabled: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // Device QA drives real data; an app open ad would cover every launch,
        // so it appears there only when a test asks for it.
        if arguments.contains("-device-qa") { return arguments.contains("-device-qa-ads") }
        return !arguments.contains("-disable-test-ads")
            && !arguments.contains(where: { $0.hasPrefix("-uitest-") })
        #else
        return true
        #endif
    }
}

import Foundation

enum AdPolicy {
    #if DEBUG
    /// Google's official adaptive banner test unit keeps development traffic out of production.
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    #else
    static let bannerUnitID = "ca-app-pub-6169297934919363/8606002846"
    #endif
    static let placement = "today_footer"

    static var isEnabled: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-device-qa"), arguments.contains("-device-qa-ads") { return true }
        return !arguments.contains("-disable-test-ads")
            && !arguments.contains(where: { $0.hasPrefix("-uitest-") })
        #else
        return true
        #endif
    }
}

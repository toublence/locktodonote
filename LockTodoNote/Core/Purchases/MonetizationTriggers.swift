import Foundation
import LockTodoNoteShared

/// One-shot paywall and reward moments. Each `claim` returns true at most once per install.
struct MonetizationTriggers {
    private let defaults: UserDefaults?
    private static let dismissedAtKey = "locktodonote.paywall.dismissed_at.v1"

    func allowsAutomaticPrompt(now: Date = Date()) -> Bool {
        guard let dismissedAt = defaults?.object(forKey: Self.dismissedAtKey) as? Date else { return true }
        return now.timeIntervalSince(dismissedAt) >= 7 * 24 * 60 * 60
    }

    func recordPaywallDismissal(now: Date = Date()) {
        defaults?.set(now, forKey: Self.dismissedAtKey)
    }

    init(store: AppGroupStore = AppGroupStore()) {
        self.defaults = store.defaults
    }

    /// Right after the user's first successful Lock Screen card — the moment
    /// the app has actually demonstrated what it does.
    func claimFirstLockScreenSuccess() -> Bool {
        claimOnce(FlutterPreferenceKeys.paywallFirstLockScreenSuccess)
    }

    /// The 24-hour preview has lapsed — the user just lost something they used.
    func claimTrialExpired(now: Date = Date()) -> Bool {
        guard
            let defaults,
            !defaults.bool(forKey: FlutterPreferenceKeys.paywallTrialExpired),
            defaults.bool(forKey: FlutterPreferenceKeys.temporaryProTrialClaimed),
            let stored = defaults.string(forKey: FlutterPreferenceKeys.temporaryProTrialExpiresAt),
            let expiry = FlutterDate.parse(stored),
            expiry <= now
        else { return false }

        defaults.set(true, forKey: FlutterPreferenceKeys.paywallTrialExpired)
        return true
    }

    /// Widget installation grants a fresh trial, so the expiry prompt is armed
    /// again for that new window.
    func rearmTrialExpiredPrompt() {
        defaults?.set(false, forKey: FlutterPreferenceKeys.paywallTrialExpired)
    }

    func claimWidgetInstallReward() -> Bool {
        claimOnce(FlutterPreferenceKeys.widgetInstallationHandled)
    }

    func claimReviewRequest() -> Bool {
        guard let defaults, !defaults.bool(forKey: FlutterPreferenceKeys.reviewRequested) else {
            return false
        }
        let successfulUses = defaults.integer(forKey: FlutterPreferenceKeys.reviewSuccessfulUses) + 1
        defaults.set(successfulUses, forKey: FlutterPreferenceKeys.reviewSuccessfulUses)
        guard successfulUses >= 3 else { return false }
        defaults.set(true, forKey: FlutterPreferenceKeys.reviewRequested)
        return true
    }

    private func claimOnce(_ key: String) -> Bool {
        guard let defaults, !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        return true
    }
}

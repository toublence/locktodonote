import Foundation
import LockTodoNoteShared

/// One-shot paywall moments.
///
/// The Flutter build defined all three of these and never called two of them,
/// so the app effectively asked for money only from Settings and a day-two
/// snackbar. Each `claim` returns true at most once per install.
struct MonetizationTriggers {
    private let defaults: UserDefaults?

    init(store: AppGroupStore = AppGroupStore()) {
        self.defaults = store.defaults
    }

    /// Right after the user's first successful Lock Screen card — the moment
    /// the app has actually demonstrated what it does.
    func claimFirstLockScreenSuccess() -> Bool {
        claimOnce(FlutterPreferenceKeys.paywallFirstLockScreenSuccess)
    }

    /// Second calendar day after install, once activation is done.
    func claimDayTwo(now: Date = Date()) -> Bool {
        guard
            let defaults,
            !defaults.bool(forKey: FlutterPreferenceKeys.paywallDayTwoFirstOpen),
            let stored = defaults.string(forKey: FlutterPreferenceKeys.installDate),
            let installed = FlutterDate.parse(stored)
        else { return false }

        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: installed),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        guard days >= 1 else { return false }

        defaults.set(true, forKey: FlutterPreferenceKeys.paywallDayTwoFirstOpen)
        return true
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

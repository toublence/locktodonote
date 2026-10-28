import GoogleMobileAds
import LockTodoNoteShared
import SwiftUI
import UIKit
import UserMessagingPlatform
import AppTrackingTransparency
@preconcurrency import FBAudienceNetwork

/// Owns the app's only ad: an app open ad shown when the app launches or comes
/// back from the background, at most once per `AdPolicy.appOpenCooldown`, and
/// never to Pro users.
///
/// One ad is kept preloaded so a return to the app shows it at once. When none
/// is ready, the launch cover holds the app back for up to
/// `AdPolicy.appOpenMaxWait` while one loads.
@MainActor
final class AdService: NSObject, ObservableObject {
    #if DEBUG
    @Published private(set) var qaLastEvent = "none"
    #endif
    @Published private(set) var isReady = false
    @Published private(set) var isGatheringConsent = false
    @Published private(set) var requiresPrivacyOptions = false
    @Published private(set) var eligibilityRevision = 0
    /// True from the moment an app open ad is due until it is dismissed or
    /// skipped. Deep links and system prompts wait for it, so nothing opens
    /// underneath the ad.
    @Published private(set) var isAppOpenInProgress = false
    private(set) var isEligible = false

    private let analytics: AnalyticsService
    private let cover = AppOpenAdCover()
    /// Moments an ad must never cover, such as onboarding or a purchase sheet.
    private var isPresentationBlocked: @MainActor () -> Bool = { false }
    private var didUpdateConsent = false
    private var didStartSDK = false
    private var isPro: Bool
    private var entitlementResolved = false
    private var lastConsentAttempt: Date?

    private var appOpenAd: AppOpenAd?
    private var appOpenLoadedAt: Date?
    private var presentedAd: AppOpenAd?
    private var isLoadingAd = false
    private var loadFailures = 0
    private var loadRetryTask: Task<Void, Never>?
    private var attemptTask: Task<Void, Never>?
    private var attemptID = 0
    /// A cold launch is an app open too.
    private var isAppOpenPending = true
    private static let lastShownKey = "locktodonote.ads.appOpen.lastShownAt"

    /// `cachedIsPro` is the last verified entitlement, so a Pro user never sees
    /// the launch cover. Presenting still waits for StoreKit's answer.
    init(analytics: AnalyticsService, cachedIsPro: Bool) {
        self.analytics = analytics
        isPro = cachedIsPro
        super.init()
        #if DEBUG
        // Device QA relaunches back to back and must see the ad every time.
        if ProcessInfo.processInfo.arguments.contains("-device-qa-ads") {
            UserDefaults.standard.removeObject(forKey: Self.lastShownKey)
        }
        #endif
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appWillEnterForeground),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// Called once the app knows whether onboarding is showing. A due cold
    /// launch is marked in progress now, before any deep link gets routed.
    func configure(isPresentationBlocked: @escaping @MainActor () -> Bool) {
        self.isPresentationBlocked = isPresentationBlocked
        if isAppOpenPending, isAppOpenDue { isAppOpenInProgress = true }
    }

    func updateEntitlement(isPro: Bool, resolved: Bool) {
        self.isPro = isPro
        entitlementResolved = resolved
        updateEligibility()
    }

    private func updateEligibility() {
        let eligible = AdPolicy.isEnabled && entitlementResolved && !isPro
        if isPro {
            discardAppOpenAd()
            isAppOpenPending = false
            cancelAppOpenAttempt()
        }
        guard eligible != isEligible else { return }
        isEligible = eligible
        isReady = eligible && didStartSDK && ConsentInformation.shared.canRequestAds
        eligibilityRevision += 1
        loadAppOpenAdIfNeeded()
    }

    // MARK: - App open opportunities

    @objc private func appWillEnterForeground() {
        // The SDK reports every dismissal; a lost callback must still not
        // leave deep links waiting forever.
        if presentedAd != nil, cover.hostViewController?.presentedViewController == nil {
            presentedAd = nil
            finishAppOpen()
        }
        isAppOpenPending = true
        beginAppOpenIfDue()
    }

    @objc private func appDidBecomeActive() {
        beginAppOpenIfDue()
        loadAppOpenAdIfNeeded()
    }

    @objc private func appDidEnterBackground() {
        isAppOpenPending = false
        cancelAppOpenAttempt()
    }

    private var isAppOpenDue: Bool {
        guard AdPolicy.isEnabled, !isPro, !isPresentationBlocked() else { return false }
        guard let last = UserDefaults.standard.object(forKey: Self.lastShownKey) as? Date else { return true }
        let elapsed = Date().timeIntervalSince(last)
        // A clock set backwards must not hold ads back indefinitely.
        return elapsed >= AdPolicy.appOpenCooldown || elapsed < 0
    }

    private func beginAppOpenIfDue() {
        guard isAppOpenPending, presentedAd == nil, attemptTask == nil else { return }
        guard isAppOpenDue else {
            isAppOpenPending = false
            isAppOpenInProgress = false
            return
        }
        isAppOpenInProgress = true
        // Windows can be covered only once the scene is active.
        guard UIApplication.shared.applicationState == .active else { return }
        isAppOpenPending = false
        attemptID += 1
        let id = attemptID
        attemptTask = Task { [weak self] in
            await self?.runAppOpenAttempt()
            self?.attemptDidEnd(id)
        }
    }

    private func runAppOpenAttempt() async {
        guard cover.show(waiting: usableAppOpenAd == nil) else {
            record("ad_show_failed")
            return
        }
        let deadline = Date().addingTimeInterval(AdPolicy.appOpenMaxWait)
        let failuresBefore = loadFailures
        var requestedPreparation = false
        while !Task.isCancelled {
            guard isAppOpenDue, UIApplication.shared.applicationState == .active else { return }
            if isEligible, let ad = usableAppOpenAd {
                if present(ad) { return }
            } else if loadFailures > failuresBefore {
                // This app open's request failed; the retry serves the next one.
                return
            } else if isEligible {
                if isReady {
                    loadAppOpenAdIfNeeded()
                } else if !requestedPreparation {
                    requestedPreparation = true
                    Task { await prepareIfNeeded() }
                }
            }
            guard Date() < deadline else {
                record("ad_show_timeout")
                return
            }
            cover.setWaiting(true)
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func attemptDidEnd(_ id: Int) {
        guard id == attemptID else { return }
        attemptTask = nil
        if presentedAd == nil { finishAppOpen() }
    }

    private func cancelAppOpenAttempt() {
        attemptID += 1
        attemptTask?.cancel()
        attemptTask = nil
        if presentedAd == nil { finishAppOpen() }
    }

    private func finishAppOpen() {
        cover.hide()
        isAppOpenInProgress = false
    }

    /// Returns whether the ad is now on screen.
    private func present(_ ad: AppOpenAd) -> Bool {
        discardAppOpenAd()
        guard let host = cover.hostViewController else { return false }
        do {
            try ad.canPresent(from: host)
        } catch {
            record("ad_show_failed", errorCode: (error as NSError).code)
            loadAppOpenAdIfNeeded()
            return false
        }
        presentedAd = ad
        ad.fullScreenContentDelegate = self
        ad.present(from: host)
        return true
    }

    // MARK: - Loading

    private var usableAppOpenAd: AppOpenAd? {
        guard let appOpenAd, let appOpenLoadedAt,
              Date().timeIntervalSince(appOpenLoadedAt) < AdPolicy.appOpenLifetime else { return nil }
        return appOpenAd
    }

    private func discardAppOpenAd() {
        appOpenAd = nil
        appOpenLoadedAt = nil
    }

    private func loadAppOpenAdIfNeeded() {
        guard isReady, isEligible, !isLoadingAd, usableAppOpenAd == nil,
              UIApplication.shared.applicationState != .background else { return }
        discardAppOpenAd()
        loadRetryTask?.cancel()
        loadRetryTask = nil
        isLoadingAd = true
        record("ad_requested")
        refreshMetaPrivacy()
        Task {
            do {
                // UMP's stored choices and OS ATT status govern this request.
                let ad = try await AppOpenAd.load(with: AdPolicy.appOpenUnitID, request: Request())
                didLoad(ad)
            } catch {
                didFailToLoad(error)
            }
        }
    }

    private func didLoad(_ ad: AppOpenAd) {
        isLoadingAd = false
        loadFailures = 0
        guard isEligible else { return }
        ad.fullScreenContentDelegate = self
        ad.paidEventHandler = { [weak self] value in
            let amount = value.value.decimalValue
            let currency = value.currencyCode
            let precision = Int(value.precision.rawValue)
            Task { @MainActor in self?.recordRevenue(value: amount, currency: currency, precision: precision) }
        }
        appOpenAd = ad
        appOpenLoadedAt = Date()
        record("ad_loaded")
    }

    private func didFailToLoad(_ error: Error) {
        isLoadingAd = false
        loadFailures += 1
        record("ad_failed", errorCode: (error as NSError).code)
        // 5s, 10s, 20s, 40s, then once a minute while the app stays open.
        let delay = min(60, 5 * pow(2, Double(min(loadFailures, 5) - 1)))
        loadRetryTask?.cancel()
        loadRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.loadRetryTask = nil
            self?.loadAppOpenAdIfNeeded()
        }
    }

    // MARK: - Consent and SDK start

    func prepareIfNeeded() async {
        guard isEligible, UIApplication.shared.applicationState != .background,
              !isGatheringConsent else { return }
        if didUpdateConsent {
            await startSDKIfAllowed()
            return
        }
        // A choice stored by an earlier launch already allows requests, so the
        // launch ad does not wait for the consent round trip below.
        if ConsentInformation.shared.canRequestAds {
            Task { await startSDKIfAllowed() }
        }
        guard lastConsentAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastConsentAttempt = Date()
        isGatheringConsent = true
        defer { isGatheringConsent = false }
        let parameters = RequestParameters()
        let updated = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.analytics.adEvent("ad_consent_failed", errorCode: (error as NSError).code)
                    }
                    continuation.resume(returning: error == nil)
                }
            }
        }
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard isEligible, UIApplication.shared.applicationState != .background else { return }
        guard updated else {
            // UMP can retain a valid prior choice when an update fails offline.
            await startSDKIfAllowed()
            return
        }
        if ConsentInformation.shared.consentStatus == .required {
            // The consent form belongs over the app itself, not the launch cover.
            cancelAppOpenAttempt()
        }
        do {
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            analytics.adEvent("ad_consent_failed", errorCode: (error as NSError).code)
            await startSDKIfAllowed()
            return
        }
        didUpdateConsent = true
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        // UMP may present a configured ATT message. Never infer ATT permission
        // from GDPR consent or request IDFA directly; the SDK respects OS status.
        await startSDKIfAllowed()
    }

    private func startSDKIfAllowed() async {
        guard isEligible, ConsentInformation.shared.canRequestAds else {
            isReady = false
            discardAppOpenAd()
            return
        }
        guard UIApplication.shared.applicationState != .background else { return }
        refreshMetaPrivacy()
        if !didStartSDK {
            // Preserve the existing first-party identifier opt-out in all builds.
            MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
            // The completion only reports mediation adapters, and none of the
            // linked ones serves app open ads. Waiting for it would tie the
            // launch ad to the slowest adapter, so the request goes out now.
            MobileAds.shared.start(completionHandler: nil)
            didStartSDK = true
        }
        isReady = isEligible && ConsentInformation.shared.canRequestAds
        loadAppOpenAdIfNeeded()
    }

    func refreshMetaPrivacy() {
        // On iOS 17+, Meta reads ATT directly. Earlier supported versions
        // require this explicit flag; UMP consent is not an ATT grant.
        if #unavailable(iOS 17) {
            FBAdSettings.setAdvertiserTrackingEnabled(ATTrackingManager.trackingAuthorizationStatus == .authorized)
        }
        // Conservative Meta Limited Data Use with Meta's geolocation.
        // This does not replace UMP's additional-consent partner settings.
        FBAdSettings.setDataProcessingOptions(["LDU"], country: 0, state: 0)
    }

    func presentPrivacyOptions() async throws {
        guard !isGatheringConsent, UIApplication.shared.applicationState == .active else { return }
        isGatheringConsent = true
        defer { isGatheringConsent = false }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        } catch {
            await startSDKIfAllowed()
            throw error
        }
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        await startSDKIfAllowed()
    }

    func record(_ name: String, errorCode: Int? = nil, placement: String = AdPolicy.placement) {
        #if DEBUG
        qaLastEvent = name + (errorCode.map { ":\($0)" } ?? "")
        #endif
        analytics.adEvent(name, errorCode: errorCode, consentState: Int(ConsentInformation.shared.consentStatus.rawValue), placement: placement)
    }

    func recordRevenue(value: Decimal, currency: String, precision: Int, placement: String = AdPolicy.placement) {
        analytics.adRevenue(
            value: value,
            currency: currency,
            precision: precision,
            placement: placement
        )
    }
}

extension AdService: FullScreenContentDelegate {
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        UserDefaults.standard.set(Date(), forKey: Self.lastShownKey)
        record("ad_impression_observed")
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        record("ad_show_failed", errorCode: (error as NSError).code)
        guard ad === presentedAd else { return }
        presentedAd = nil
        finishAppOpen()
        loadAppOpenAdIfNeeded()
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        // Let the app show through the dismissal animation.
        cover.setWaiting(false)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard ad === presentedAd else { return }
        presentedAd = nil
        // The cooldown runs from when the user got the app back.
        UserDefaults.standard.set(Date(), forKey: Self.lastShownKey)
        finishAppOpen()
        loadAppOpenAdIfNeeded()
    }
}

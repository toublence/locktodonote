import GoogleMobileAds
import LockTodoNoteShared
import SwiftUI
import UIKit
import UserMessagingPlatform
import AppTrackingTransparency
@preconcurrency import FBAudienceNetwork

@MainActor
final class AdService: ObservableObject {
    #if DEBUG
    @Published private(set) var qaLastEvent = "none"
    @Published private(set) var qaMetaAdapter = "pending"
    @Published private(set) var qaAdSource = "none"
    @Published private(set) var qaResponse = "none"
    #endif
    @Published private(set) var isReady = false
    @Published private(set) var isGatheringConsent = false
    @Published private(set) var requiresPrivacyOptions = false
    @Published private(set) var eligibilityRevision = 0
    private(set) var isEligible = false

    private let analytics: AnalyticsService
    private var sessionCanShowAds: Bool
    private var didUpdateConsent = false
    private var didStartSDK = false
    private var isPro = false
    private var entitlementResolved = false
    private var lastConsentAttempt: Date?

    init(analytics: AnalyticsService) {
        self.analytics = analytics
        sessionCanShowAds = analytics.hasCompletedActivation
    }

    func updateEntitlement(isPro: Bool, resolved: Bool) {
        self.isPro = isPro
        entitlementResolved = resolved
        updateEligibility()
    }

    func startNextSession() {
        sessionCanShowAds = analytics.hasCompletedActivation
        updateEligibility()
    }

    private func updateEligibility() {
        let eligible = AdPolicy.isEnabled && entitlementResolved && !isPro && sessionCanShowAds
        guard eligible != isEligible else { return }
        isEligible = eligible
        isReady = eligible && didUpdateConsent && !isGatheringConsent && didStartSDK && ConsentInformation.shared.canRequestAds
        eligibilityRevision += 1
    }

    func prepareIfNeeded() async {
        guard isEligible, UIApplication.shared.applicationState == .active,
              !isGatheringConsent else { return }
        isGatheringConsent = true
        defer { isGatheringConsent = false }
        if didUpdateConsent {
            await startSDKIfAllowed()
            return
        }
        guard lastConsentAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastConsentAttempt = Date()
        isReady = false
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
        guard isEligible, UIApplication.shared.applicationState == .active else { return }
        guard updated else {
            // UMP can retain a valid prior choice when an update fails offline.
            await startSDKIfAllowed()
            return
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
        guard isEligible, ConsentInformation.shared.canRequestAds,
              UIApplication.shared.applicationState == .active else {
            isReady = false
            return
        }
        refreshMetaPrivacy()
        if !didStartSDK {
            #if DEBUG
            if AdPolicy.isMetaQA { MetaMediationQA.configureTestDevices() }
            #endif
            // Preserve the existing first-party identifier opt-out in all builds.
            MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                MobileAds.shared.start { _ in continuation.resume() }
            }
            didStartSDK = true
            #if DEBUG
            let statuses = MobileAds.shared.initializationStatus.adapterStatusesByClassName
            qaMetaAdapter = statuses.filter { $0.key.lowercased().contains("facebook") || $0.key.lowercased().contains("meta") }
                .map { "\($0.key):\($0.value.state == .ready ? "ready" : "not_ready") \($0.value.description)" }
                .sorted().joined(separator: "\n")
            if qaMetaAdapter.isEmpty { qaMetaAdapter = "missing" }
            print("META_QA adapter: \(qaMetaAdapter)")
            #endif
        }
        isReady = isEligible && ConsentInformation.shared.canRequestAds
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

    #if DEBUG
    func recordResponse(_ response: ResponseInfo?) {
        qaAdSource = response?.loadedAdNetworkResponseInfo?.adNetworkClassName ?? "none"
        qaResponse = response?.description ?? "none"
        if AdPolicy.isMetaQA { print("META_QA response: \(qaResponse)") }
    }
    #endif

    func presentPrivacyOptions() async throws {
        guard !isGatheringConsent, UIApplication.shared.applicationState == .active else { return }
        isReady = false
        eligibilityRevision += 1
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

import GoogleMobileAds
import LockTodoNoteShared
import SwiftUI
import UIKit
import UserMessagingPlatform

@MainActor
final class AdService: ObservableObject {
    #if DEBUG
    @Published private(set) var qaLastEvent = "none"
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
        isReady = eligible && didStartSDK && ConsentInformation.shared.canRequestAds
        eligibilityRevision += 1
    }

    func prepareIfNeeded() async {
        guard isEligible, UIApplication.shared.applicationState == .active,
              !isGatheringConsent else { return }
        if didUpdateConsent {
            await startSDKIfAllowed()
            return
        }
        isGatheringConsent = true
        defer { isGatheringConsent = false }
        let parameters = RequestParameters()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.analytics.adEvent("ad_consent_failed", errorCode: (error as NSError).code)
                    }
                    continuation.resume()
                }
            }
        }
        guard isEligible, UIApplication.shared.applicationState == .active else { return }
        do {
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            analytics.adEvent("ad_consent_failed", errorCode: (error as NSError).code)
        }
        didUpdateConsent = true
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        // Test ads do not need an IDFA. Do not request ATT solely for QA.
        // Production tracking must be configured with its own disclosures and UMP flow.
        await startSDKIfAllowed()
    }

    private func startSDKIfAllowed() async {
        guard isEligible, ConsentInformation.shared.canRequestAds,
              UIApplication.shared.applicationState == .active else {
            isReady = false
            return
        }
        if !didStartSDK {
            // Keep the test integration independent of cross-app first-party profiling.
            MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                MobileAds.shared.start { _ in continuation.resume() }
            }
            didStartSDK = true
        }
        isReady = isEligible && ConsentInformation.shared.canRequestAds
    }

    func presentPrivacyOptions() async throws {
        isReady = false
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

#if DEBUG
import SwiftUI
import UIKit
import CryptoKit
import AdSupport
import AppTrackingTransparency
import GoogleMobileAds
@preconcurrency import FBAudienceNetwork

/// Explicit device QA only. Release never registers devices or uses this UI.
@MainActor
enum MetaMediationQA {
    static func configureTestDevices() {
        FBAdSettings.addTestDevice(FBAdSettings.testDeviceHash())
        // Register public, app-scoped identifier hashes as test candidates.
        // Ad Inspector must successfully open before this QA UI can load an ad;
        // that validates Google's test-device registration instead of assuming it.
        var identifiers = [UIDevice.current.identifierForVendor?.uuidString].compactMap { $0 }
        if ATTrackingManager.trackingAuthorizationStatus == .authorized {
            identifiers.append(ASIdentifierManager.shared().advertisingIdentifier.uuidString)
        }
        let variants = identifiers.flatMap { [$0, $0.lowercased(), $0.replacingOccurrences(of: "-", with: "")] }
        let hashes = variants.flatMap { value -> [String] in
            let hash = Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
            return [hash, hash.uppercased()]
        }
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = Array(Set(hashes + [FBAdSettings.testDeviceHash()]))
    }
}

struct MetaMediationQAView: View {
    @EnvironmentObject private var ads: AdService
    @State private var inspectorStatus = "not_opened"
    @State private var inspectorValidated = false
    @State private var loadBanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Meta mediation device QA").font(.title2.bold())
                Text("UMP ready=\(ads.isReady); ATT=\(ATTrackingManager.trackingAuthorizationStatus.rawValue)")
                    .accessibilityIdentifier("meta.qa.consent")
                Text(ads.qaMetaAdapter).accessibilityIdentifier("meta.qa.adapter")
                Text("Meta test=\(FBAdSettings.isTestMode())")
                    .accessibilityIdentifier("meta.qa.testMode")
                Button("Open Ad Inspector") {
                    MobileAds.shared.presentAdInspector(from: nil) { error in
                        Task { @MainActor in
                            inspectorStatus = error.map { "\(($0 as NSError).domain):\(($0 as NSError).code) \($0.localizedDescription)" } ?? "closed"
                            inspectorValidated = error == nil
                            print("META_QA inspector: \(inspectorStatus)")
                        }
                    }
                }
                .disabled(!ads.isReady)
                .accessibilityIdentifier("meta.qa.inspector")
                Text(inspectorStatus).accessibilityIdentifier("meta.qa.inspectorStatus")
                Text("Choose Meta Audience Network (Bidding) single-source testing in Ad Inspector before loading.")
                Button("Load mediation test banner") { loadBanner = true }
                    .disabled(!ads.isReady || !inspectorValidated)
                    .accessibilityIdentifier("meta.qa.load")
                if loadBanner {
                    AdaptiveBannerView(placement: "meta_qa")
                }
                Text(ads.qaLastEvent).accessibilityIdentifier("meta.qa.event")
                Text(ads.qaAdSource).accessibilityIdentifier("meta.qa.source")
                Text(ads.qaResponse).font(.caption.monospaced())
                    .accessibilityIdentifier("meta.qa.response")
            }
            .padding(24)
        }
    }
}
#endif

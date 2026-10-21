import GoogleMobileAds
import SwiftUI
import UIKit

/// Main app content owns ad slots; extensions and input sheets never embed ads.
struct AdaptiveBannerView: View {
    var placement: String = AdPolicy.placement
    private let bannerHeight: CGFloat = 60
    @EnvironmentObject private var ads: AdService
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var isLoaded = false
    @State private var didFail = false
    @State private var retryCount = 0

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, floor(geometry.size.width))
            let size = inlineAdaptiveBanner(width: width, maxHeight: bannerHeight)
            VStack(spacing: 0) {
                if ads.isReady && isVisible && scenePhase == .active && !didFail {
                    BannerContainer(adSize: size, ads: ads, placement: placement, isLoaded: $isLoaded, didFail: $didFail)
                        .id("\(width)_\(ads.eligibilityRevision)")
                        .frame(width: width, height: bannerHeight)
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(isLoaded ? 1 : 0)
            .onAppear { updateVisibility(geometry.frame(in: .global)) }
            .onChange(of: geometry.frame(in: .global)) { updateVisibility($0) }
        }
        // A collapsed loading/failure slot does not reserve an empty ad rectangle.
        .frame(height: isLoaded && isVisible && ads.isReady ? bannerHeight : 1)
        .clipped()
        .onChange(of: ads.isReady) { _ in isLoaded = false }
        .onChange(of: isVisible) { _ in isLoaded = false }
        .onChange(of: scenePhase) { _ in isLoaded = false }
        .task(id: "\(didFail)_\(scenePhase)_\(isVisible)_\(ads.isReady)") {
            guard didFail, retryCount < 2, isVisible, ads.isReady, scenePhase == .active else { return }
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard !Task.isCancelled else { return }
            retryCount += 1
            didFail = false
        }
        .accessibilityIdentifier("ads.\(placement.replacingOccurrences(of: "_footer", with: ""))Banner")
    }

    private func updateVisibility(_ frame: CGRect) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else {
            isVisible = false
            return
        }
        isVisible = !frame.isEmpty && window.bounds.intersects(frame)
    }
}

private struct BannerContainer: UIViewRepresentable {
    let adSize: AdSize
    let ads: AdService
    let placement: String
    @Binding var isLoaded: Bool
    @Binding var didFail: Bool

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdPolicy.bannerUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        banner.delegate = context.coordinator
        let placement = placement
        banner.paidEventHandler = { [weak ads] value in
            let amount = value.value.decimalValue
            let currency = value.currencyCode
            let precision = Int(value.precision.rawValue)
            Task { @MainActor in ads?.recordRevenue(value: amount, currency: currency, precision: precision, placement: placement) }
        }
        ads.record("ad_requested", placement: placement)
        ads.refreshMetaPrivacy()
        // UMP's stored choices and OS ATT status govern this request.
        banner.load(Request())
        return banner
    }

    func updateUIView(_ view: BannerView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ view: BannerView, coordinator: Coordinator) {
        view.delegate = nil
        view.paidEventHandler = nil
        view.removeFromSuperview()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        var parent: BannerContainer
        init(parent: BannerContainer) { self.parent = parent }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            parent.isLoaded = true
            #if DEBUG
            parent.ads.recordResponse(bannerView.responseInfo)
            #endif
            parent.ads.record("ad_loaded", placement: parent.placement)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            parent.isLoaded = false
            parent.didFail = true
            #if DEBUG
            parent.ads.recordResponse((error as NSError).userInfo[GADErrorUserInfoKeyResponseInfo] as? ResponseInfo)
            #endif
            parent.ads.record("ad_failed", errorCode: (error as NSError).code, placement: parent.placement)
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            parent.ads.record("ad_impression_observed", placement: parent.placement)
        }
    }
}

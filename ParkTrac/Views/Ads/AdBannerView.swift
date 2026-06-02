import SwiftUI

// MARK: - Ad Banner
//
// Requires the Google Mobile Ads SDK (Swift Package):
//   File → Add Package Dependencies → https://github.com/googleads/swift-package-manager-google-mobile-ads
//
// Renders nothing until the SDK is present and initialised via
// MobileAds.shared.start() in ParkTracApp.init().

struct AdBannerView: View {
    let store = StoreService.shared

    var body: some View {
        #if canImport(GoogleMobileAds)
        AdBannerViewImpl(store: store)
        #else
        EmptyView()
        #endif
    }
}

#if canImport(GoogleMobileAds)
import GoogleMobileAds

private struct AdBannerViewImpl: View {
    let store: StoreService
    @State private var adLoaded = false

    var body: some View {
        if !store.isAdFree && store.adsReady {
            ZStack {
                BannerAdRepresentable(adLoaded: $adLoaded)
                    .frame(height: 50)
            }
            .frame(height: adLoaded ? 50 : 0)
            .clipped()
            .animation(.easeIn(duration: 0.25), value: adLoaded)
        }
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    @Binding var adLoaded: Bool

    #if DEBUG
    private let adUnitID = "ca-app-pub-3940256099942544/2934735716"
    #else
    private let adUnitID = "ca-app-pub-8284895327083883/3463130685"
    #endif

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        if banner.rootViewController == nil {
            banner.rootViewController = topViewController()
        }
        guard !adLoaded else { return }
        banner.load(Request())
    }

    func makeCoordinator() -> Coordinator { Coordinator(adLoaded: $adLoaded) }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }
        var top: UIViewController = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var adLoaded: Bool
        init(adLoaded: Binding<Bool>) { _adLoaded = adLoaded }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            DispatchQueue.main.async { self.adLoaded = true }
        }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            DispatchQueue.main.async { self.adLoaded = false }
        }
    }
}
#endif

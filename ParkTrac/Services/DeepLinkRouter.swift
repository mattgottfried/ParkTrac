import Foundation
import UserNotifications

// MARK: - Deep Links

/// App destinations reachable from `thrilltrack://` URLs (Live Activities, Shortcuts),
/// notification taps, and the in-app banners.
///
/// URL forms: `thrilltrack://waittimes`, `thrilltrack://ride/<rideId>`,
/// `thrilltrack://timer`, `thrilltrack://plan`, `thrilltrack://dining`, `thrilltrack://settings`
enum DeepLink: Equatable {
    case waitTimes
    case ride(id: String)
    /// The ride currently being timed (`AppState.activeTimerRideId`)
    case activeTimer
    case plan
    case dining
    case settings

    static let scheme = "thrilltrack"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host?.lowercased() {
        case "waittimes": self = .waitTimes
        case "ride":
            guard let id = parts.first, !id.isEmpty else { self = .waitTimes; return }
            self = .ride(id: id)
        case "timer":     self = .activeTimer
        case "plan":      self = .plan
        case "dining":    self = .dining
        case "settings":  self = .settings
        default:          return nil
        }
    }

    var url: URL {
        switch self {
        case .waitTimes:       return URL(string: "\(Self.scheme)://waittimes")!
        case .ride(let id):
            let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            return URL(string: "\(Self.scheme)://ride/\(safe)")!
        case .activeTimer:     return URL(string: "\(Self.scheme)://timer")!
        case .plan:            return URL(string: "\(Self.scheme)://plan")!
        case .dining:          return URL(string: "\(Self.scheme)://dining")!
        case .settings:        return URL(string: "\(Self.scheme)://settings")!
        }
    }

    /// Key under which notifications carry their link in `userInfo`.
    static let userInfoKey = "deepLink"
}

// MARK: - Router

/// Single inbox for navigation requests. `ContentView` consumes `pending` (switching tabs);
/// destination views consume their own follow-ups (`pendingRideId`, `showDining`).
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// Set by anyone who wants to navigate; cleared by ContentView once handled.
    var pending: DeepLink?
    /// Ride sheet ParkMapView should open once that ride is loaded.
    var pendingRideId: String?
    /// StatsView pushes MyDiningView while true.
    var showDining = false
    /// Bumped when the Wait Times tab is tapped while already selected.
    var waitTimesReselectCount = 0

    private init() {}

    func open(_ link: DeepLink) { pending = link }

    @discardableResult
    func open(url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        pending = link
        return true
    }
}

// MARK: - Notification Delegate

/// Routes notification taps into the router and lets alerts show while the app is open
/// (ride-wait alerts fire from the foreground refresh, so without this they were silent).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo[DeepLink.userInfoKey] as? String,
              let url = URL(string: raw) else { return }
        await MainActor.run { _ = DeepLinkRouter.shared.open(url: url) }
    }
}

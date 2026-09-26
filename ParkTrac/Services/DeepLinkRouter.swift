import Foundation
import UIKit
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

    /// Buttons on wait-drop alerts for DAS / AAP holders. Registered at launch.
    static func registerCategories() {
        let openUniversal = UNNotificationAction(
            identifier: NotificationKeys.openBookingAppAction,
            title: "Book in Universal App", options: [.foreground])
        let openDisney = UNNotificationAction(
            identifier: NotificationKeys.openBookingAppAction,
            title: "Book in Disney App", options: [.foreground])
        // Runs in the background — logs without opening ThrillTrack
        let logged = UNNotificationAction(
            identifier: NotificationKeys.loggedReturnAction,
            title: "I Booked It — Log Return", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: NotificationKeys.aapWaitCategory,
                                   actions: [openUniversal, logged], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationKeys.dasWaitCategory,
                                   actions: [openDisney, logged], intentIdentifiers: []),
        ])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case NotificationKeys.openBookingAppAction:
            guard let pass = Self.accessPass(from: info) else { return }
            await MainActor.run {
                // Land on the ride when they come back, then hand off to the resort's app
                if let raw = info[DeepLink.userInfoKey] as? String, let url = URL(string: raw) {
                    _ = DeepLinkRouter.shared.open(url: url)
                }
                pass.bookingApp.open()
            }

        case NotificationKeys.loggedReturnAction:
            guard let pass = Self.accessPass(from: info),
                  let resortRaw = info[NotificationKeys.resort] as? String,
                  let resort = ParkGroup(rawValue: resortRaw),
                  let rideId = info[NotificationKeys.rideId] as? String,
                  let rideName = info[NotificationKeys.rideName] as? String else { return }
            let parkName = info[NotificationKeys.parkName] as? String ?? ""
            let postedWait = info[NotificationKeys.postedWait] as? Int
            await MainActor.run {
                let returnStart = ReturnTimeLogger.logAccessPassNow(
                    pass, rideId: rideId, rideName: rideName, parkName: parkName,
                    resort: resort, postedWait: postedWait,
                    context: PersistenceController.container.mainContext)
                NotificationService.shared.confirmAccessPassLogged(
                    passLabel: pass.label, rideName: rideName, returnStart: returnStart)
            }

        default:
            guard let raw = info[DeepLink.userInfoKey] as? String,
                  let url = URL(string: raw) else { return }
            await MainActor.run { _ = DeepLinkRouter.shared.open(url: url) }
        }
    }

    private static func accessPass(from info: [AnyHashable: Any]) -> AccessPass? {
        guard let raw = info[NotificationKeys.resort] as? String,
              let resort = ParkGroup(rawValue: raw) else { return nil }
        return AccessPass.held(at: resort) ?? (resort == .universal ? .aap : .das)
    }
}

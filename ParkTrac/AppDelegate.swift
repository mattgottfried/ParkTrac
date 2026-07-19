import UIKit
import CloudKit

/// Only exists for silent-push plumbing behind household sharing — registers for remote
/// notifications when a household is joined, and routes CloudKit's silent pushes into
/// `HouseholdSyncService`. Nothing else in the app depends on this.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if HouseholdSyncService.shared.currentCode != nil {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // No APNs token storage needed — CloudKit subscriptions route pushes automatically
        // once the device is registered; we don't run our own push server.
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Best-effort feature — the foreground timer and background task remain as fallback sync paths.
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let changed = await HouseholdSyncService.shared.handleRemotePush()
            completionHandler(changed ? .newData : .noData)
        }
    }
}

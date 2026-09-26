import Foundation
import UserNotifications
import SwiftData

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func checkAlerts(rides: [DisplayRide], context: ModelContext) {
        let alerts = (try? context.fetch(FetchDescriptor<RideAlert>())) ?? []
        for alert in alerts where alert.isActive {
            guard let ride = rides.first(where: { $0.id == alert.rideId }) else { continue }
            guard ride.isOperating, let wait = ride.waitMinutes, wait <= alert.thresholdMinutes else { continue }
            fireNotification(for: alert, currentWait: wait)
            alert.isActive = false  // one-shot: deactivate after firing
        }
        try? context.save()
    }

    private func fireNotification(for alert: RideAlert, currentWait: Int) {
        let content = UNMutableNotificationContent()
        content.title = "⏱ Wait time dropped!"
        content.body = "\(alert.rideName) is now \(currentWait) min — under your \(alert.thresholdMinutes) min alert."
        content.sound = .default
        content.userInfo = [DeepLink.userInfoKey: DeepLink.ride(id: alert.rideId).url.absoluteString]
        let request = UNNotificationRequest(
            identifier: "alert-\(alert.rideId)-\(Date().timeIntervalSince1970)",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Lightning Lane watch hit: a Multi Pass return opened inside the user's window
    /// (or an earlier one than we last reported). Notify-only — booking happens in Disney's app.
    func fireLightningLaneOpening(watch: LightningLaneWatch, returnStart: Date, previous: Date?) {
        let time = returnStart.formatted(date: .omitted, time: .shortened)
        let content = UNMutableNotificationContent()
        if let previous {
            content.title = "⚡ Earlier Lightning Lane: \(watch.rideName)"
            content.body = "Return at \(time) is open now (earlier than \(previous.formatted(date: .omitted, time: .shortened))). Book it in the Disney app."
        } else {
            content.title = "⚡ Lightning Lane open: \(watch.rideName)"
            content.body = "Return at \(time) is open now, inside your \(watch.windowText) window. Book it in the Disney app."
        }
        content.sound = .default
        content.threadIdentifier = "ll-watch-\(watch.rideId)"
        content.userInfo = [DeepLink.userInfoKey: DeepLink.ride(id: watch.rideId).url.absoluteString]
        let request = UNNotificationRequest(
            identifier: "llwatch-\(watch.rideId)-\(Int(returnStart.timeIntervalSince1970))",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleLLReminder(passId: String, rideName: String, returnEnd: Date) {
        let fireAt = returnEnd.addingTimeInterval(-600)  // 10 min before window closes
        guard fireAt > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "⚡ Lightning Lane expiring soon"
        content.body = "\(rideName) return window closes in 10 minutes!"
        content.sound = .default
        content.userInfo = [DeepLink.userInfoKey: DeepLink.plan.url.absoluteString]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt),
            repeats: false)
        let request = UNNotificationRequest(identifier: "ll-\(passId)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelLLReminder(passId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["ll-\(passId)"])
    }

    func schedulePassRenewalReminder(resort: String, passName: String, date: Date) {
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "🎟 Pass renewal reminder"
        content.body = "\(resort) \(passName) expires in 30 days. Time to renew!"
        content.sound = .default
        content.userInfo = [DeepLink.userInfoKey: DeepLink.settings.url.absoluteString]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false)
        let request = UNNotificationRequest(identifier: "passRenewal-\(resort)-\(passName)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

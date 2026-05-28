import Foundation
import UserNotifications
import SwiftData

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    func requestAuthorization() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
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
        let request = UNNotificationRequest(
            identifier: "alert-\(alert.rideId)-\(Date().timeIntervalSince1970)",
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
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false)
        let request = UNNotificationRequest(identifier: "passRenewal-\(resort)-\(passName)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

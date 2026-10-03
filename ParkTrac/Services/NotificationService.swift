import Foundation
import UserNotifications
import SwiftData

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func checkAlerts(rides: [DisplayRide], context: ModelContext,
                     resort: ParkGroup, parkNames: [String: String] = [:]) {
        let alerts = (try? context.fetch(FetchDescriptor<RideAlert>())) ?? []
        for alert in alerts where alert.isActive {
            // The alert server pushes this one — don't double up
            guard !InstantAlertsService.shared.covers(alert.serverId) else { continue }
            guard let ride = rides.first(where: { $0.id == alert.rideId }) else { continue }
            guard ride.isOperating, let wait = ride.waitMinutes, wait <= alert.thresholdMinutes else { continue }
            fireNotification(for: alert, currentWait: wait, resort: resort,
                             parkName: parkNames[ride.parkId] ?? "")
            alert.isActive = false  // one-shot: deactivate after firing
        }
        try? context.save()
    }

    private func fireNotification(for alert: RideAlert, currentWait: Int, resort: ParkGroup, parkName: String) {
        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive   // gets through Focus (entitlement)
        content.title = "⏱ Wait time dropped!"
        content.body = "\(alert.rideName) is now \(currentWait) min — under your \(alert.thresholdMinutes) min alert."
        content.sound = .default
        content.userInfo = [
            DeepLink.userInfoKey: DeepLink.ride(id: alert.rideId).url.absoluteString,
            NotificationKeys.rideId: alert.rideId,
            NotificationKeys.rideName: alert.rideName,
            NotificationKeys.parkName: parkName,
            NotificationKeys.resort: resort.rawValue,
            NotificationKeys.postedWait: currentWait,
        ]
        // DAS/AAP holders get "Book in … App" + "I Booked It" buttons on the alert
        if let pass = AccessPass.held(at: resort) {
            content.categoryIdentifier = pass == .aap
                ? NotificationKeys.aapWaitCategory : NotificationKeys.dasWaitCategory
            content.body += " Book your \(pass.label) now to return \(pass.returnPhrase(postedWait: currentWait))."
        }
        let request = UNNotificationRequest(
            identifier: "alert-\(alert.rideId)-\(Date().timeIntervalSince1970)",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// A Must-Do ride's wait is well below its usual (GoodTimeService, once per ride per day).
    func fireGoodTimeToRide(rideId: String, rideName: String, deal: GoodTimeToRide.Deal) {
        let content = UNMutableNotificationContent()
        content.title = "🎢 Good time to ride \(rideName)"
        content.body = "\(deal.wait) min now — \(deal.longText)."
        content.sound = .default
        content.threadIdentifier = "good-time"
        content.userInfo = [
            DeepLink.userInfoKey: DeepLink.ride(id: rideId).url.absoluteString,
            NotificationKeys.rideId: rideId,
            NotificationKeys.rideName: rideName,
        ]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "goodtime-\(rideId)", content: content, trigger: nil))
    }

    /// A Must-Do ride just went down.
    func fireMustDoDown(rideId: String, rideName: String) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ \(rideName) is down"
        content.body = "One of your Must-Dos just stopped running. ThrillTrack will tell you when it's back up."
        content.sound = .default
        content.threadIdentifier = "mustdo-\(rideId)"
        content.userInfo = [
            DeepLink.userInfoKey: DeepLink.ride(id: rideId).url.absoluteString,
            NotificationKeys.rideId: rideId,
            NotificationKeys.rideName: rideName,
        ]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "mustdo-down-\(rideId)", content: content, trigger: nil))
    }

    /// A Must-Do ride that was down is running again.
    func fireMustDoBackUp(rideId: String, rideName: String, wait: Int?, downtimeMinutes: Int? = nil) {
        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive
        content.title = "✅ \(rideName) is back up"
        content.body = RideComeback.message(wait: wait, downtimeMinutes: downtimeMinutes)
        content.sound = .default
        content.threadIdentifier = "mustdo-\(rideId)"
        content.userInfo = [
            DeepLink.userInfoKey: DeepLink.ride(id: rideId).url.absoluteString,
            NotificationKeys.rideId: rideId,
            NotificationKeys.rideName: rideName,
        ]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "mustdo-up-\(rideId)", content: content, trigger: nil))
    }

    /// A round-number ride-count milestone was just crossed — one ride's own count, or the
    /// resort-wide total.
    func fireRideMilestone(rideId: String?, rideName: String, milestone: Int, overall: Bool) {
        let content = UNMutableNotificationContent()
        if overall {
            content.title = "🎉 \(milestone) rides logged!"
            content.body = "You've now logged \(milestone) rides here. Keep it up!"
        } else {
            content.title = "🎉 \(milestone)th ride on \(rideName)!"
            content.body = "That's \(milestone) times you've ridden \(rideName)."
        }
        content.sound = .default
        content.threadIdentifier = "milestone"
        if let rideId {
            content.userInfo = [
                DeepLink.userInfoKey: DeepLink.ride(id: rideId).url.absoluteString,
                NotificationKeys.rideId: rideId,
                NotificationKeys.rideName: rideName,
            ]
        }
        let identifier = "milestone-\(overall ? "overall" : (rideId ?? rideName))-\(milestone)"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// One consolidated notification per trip morning — weather, crowd level, and today's top
    /// Must-Do pick — instead of several separate banners you'd have to find in-app.
    func fireMorningBriefing(resort: ParkGroup, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "☀️ Good morning at \(resort.shortName)"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "morning-briefing"
        content.userInfo = [DeepLink.userInfoKey: DeepLink.plan.url.absoluteString]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "morning-\(resort.rawValue)-\(MorningBriefing.dayKey(.now))",
                                  content: content, trigger: nil))
    }

    /// Rain is about to arrive at the resort (once a day) — plan indoor rides.
    func fireRainHeadsUp(resort: ParkGroup, headline: String) {
        let content = UNMutableNotificationContent()
        content.title = "🌧 \(headline)"
        content.body = "Good time for indoor rides and shows — Next Up and the Smart Planner already favor them."
        content.sound = .default
        content.threadIdentifier = "rain"
        content.userInfo = [DeepLink.userInfoKey: DeepLink.plan.url.absoluteString]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "rain-\(resort.rawValue)", content: content, trigger: nil))
    }

    /// The hottest part of the day is about to arrive at the resort (once a day) — plan an
    /// indoor break.
    func fireHeatHeadsUp(resort: ParkGroup, headline: String) {
        let content = UNMutableNotificationContent()
        content.title = "☀️ \(headline)"
        content.body = "Good time for indoor rides, shows, or an AC break — Next Up and the Smart Planner already favor them."
        content.sound = .default
        content.threadIdentifier = "heat"
        content.userInfo = [DeepLink.userInfoKey: DeepLink.plan.url.absoluteString]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "heat-\(resort.rawValue)", content: content, trigger: nil))
    }

    /// A ride you were watching is operating again.
    func fireRideReopened(watch: ReopenWatch, wait: Int?) {
        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive   // gets through Focus (entitlement)
        content.title = "✅ \(watch.rideName) is back up"
        content.body = wait.map { "It's operating again — posted wait \($0) min." } ?? "It's operating again."
        content.sound = .default
        content.threadIdentifier = "reopen-\(watch.rideId)"
        content.userInfo = [
            DeepLink.userInfoKey: DeepLink.ride(id: watch.rideId).url.absoluteString,
            NotificationKeys.rideId: watch.rideId,
            NotificationKeys.rideName: watch.rideName,
            NotificationKeys.parkName: watch.parkName,
            NotificationKeys.resort: watch.resortRaw,
        ]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "reopen-\(watch.rideId)", content: content, trigger: nil))
    }

    /// Lightning Lane watch hit: a Multi Pass return opened inside the user's window
    /// (or an earlier one than we last reported). Notify-only — booking happens in Disney's app.
    func fireLightningLaneOpening(watch: LightningLaneWatch, returnStart: Date, returnEnd: Date?, previous: Date?) {
        let time = returnStart.formatted(date: .omitted, time: .shortened)
        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive   // gets through Focus (entitlement)
        let pass = watch.passName ?? "Lightning Lane"
        let app = BookingApp.for(watch.resort).appName
        if let previous {
            content.title = "⚡ Earlier \(pass): \(watch.rideName)"
            content.body = "Return at \(time) is open now (earlier than \(previous.formatted(date: .omitted, time: .shortened))). Book it in the \(app)."
        } else {
            content.title = "⚡ \(pass) open: \(watch.rideName)"
            content.body = "Return at \(time) is open now, inside your \(watch.windowText) window. Book it in the \(app)."
        }
        content.sound = .default
        content.threadIdentifier = "ll-watch-\(watch.rideId)"
        // "Book in Disney App" + "I Booked It" buttons; the log uses this exact window
        content.categoryIdentifier = NotificationKeys.llWatchCategory
        var info: [String: Any] = [
            DeepLink.userInfoKey: DeepLink.ride(id: watch.rideId).url.absoluteString,
            NotificationKeys.rideId: watch.rideId,
            NotificationKeys.rideName: watch.rideName,
            NotificationKeys.parkName: watch.parkName ?? "",
            NotificationKeys.resort: watch.resort.rawValue,
            NotificationKeys.passLabel: pass,
            NotificationKeys.returnStart: returnStart.timeIntervalSince1970,
        ]
        if let returnEnd { info[NotificationKeys.returnEnd] = returnEnd.timeIntervalSince1970 }
        content.userInfo = info
        let request = UNNotificationRequest(
            identifier: "llwatch-\(watch.rideId)-\(Int(returnStart.timeIntervalSince1970))",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// DAS/AAP: fires when the logged return time arrives.
    func scheduleReturnReady(passId: String, passLabel: String, rideName: String, at returnStart: Date) {
        guard returnStart > .now.addingTimeInterval(30) else { return }
        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive   // gets through Focus (entitlement)
        content.title = "✅ \(passLabel) return is open"
        content.body = "You can ride \(rideName) now — your return is valid until park close."
        content.sound = .default
        content.userInfo = [DeepLink.userInfoKey: DeepLink.plan.url.absoluteString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: returnStart.timeIntervalSinceNow, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "return-\(passId)", content: content, trigger: trigger))
    }

    /// Area timed entry (USJ Super Nintendo World): fires when the entry window opens.
    func scheduleAreaEntryOpen(passId: String, areaName: String, start: Date, end: Date) {
        guard start > .now.addingTimeInterval(30) else { return }
        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive   // gets through Focus (entitlement)
        content.title = "🍄 \(areaName) entry is open"
        content.body = "Head to the entrance — your timed entry window closes at \(end.formatted(date: .omitted, time: .shortened))."
        content.sound = .default
        content.userInfo = [DeepLink.userInfoKey: DeepLink.plan.url.absoluteString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: start.timeIntervalSinceNow, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "entry-\(passId)", content: content, trigger: trigger))
    }

    /// Confirmation after "I Booked It" from a notification (the app may not be open).
    func confirmAccessPassLogged(passLabel: String, rideName: String, returnStart: Date, isOpenEnded: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = "\(passLabel) logged: \(rideName)"
        let time = returnStart.formatted(date: .omitted, time: .shortened)
        let openNow = returnStart <= .now.addingTimeInterval(60)
        content.body = isOpenEnded
            ? (openNow
               ? "Your return is open now — ride any time before park close. It's in My Day."
               : "Return around \(time). It's in My Day, and we'll remind you when it opens. Adjust the time in the app if Universal/Disney gave a different one.")
            : "Return at \(time). It's in My Day, and we'll remind you 10 minutes before the window closes. Adjust it in the app if you booked a different time."
        content.userInfo = [DeepLink.userInfoKey: DeepLink.plan.url.absoluteString]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "logged-\(UUID().uuidString)", content: content, trigger: nil))
    }

    func scheduleLLReminder(passId: String, rideName: String, returnEnd: Date) {
        let fireAt = returnEnd.addingTimeInterval(-600)  // 10 min before window closes
        guard fireAt > .now else { return }
        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive   // gets through Focus (entitlement)
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

/// Checks ride-count milestones after a new `RideLog` is saved — both the ride's own count and
/// the resort-wide total — and fires `fireRideMilestone` when a round number is newly crossed.
/// UserDefaults-tracked (per ride, per resort) the same way `WaitTimeRecorder`'s DOWN transitions
/// are, so it only compares against the last-seen count rather than re-deriving history.
@MainActor
enum RideMilestoneService {
    static func checkMilestones(rideId: String, rideName: String, resort: String, context: ModelContext) {
        guard let allLogs = try? context.fetch(FetchDescriptor<RideLog>()) else { return }
        let rideCount = allLogs.filter { $0.rideId == rideId && $0.resort == resort }.count
        checkOne(key: "milestoneCount_\(resort)_\(rideId)", newCount: rideCount) { milestone in
            NotificationService.shared.fireRideMilestone(rideId: rideId, rideName: rideName, milestone: milestone, overall: false)
        }
        let overallCount = allLogs.filter { $0.resort == resort }.count
        checkOne(key: "milestoneCount_overall_\(resort)", newCount: overallCount) { milestone in
            NotificationService.shared.fireRideMilestone(rideId: nil, rideName: rideName, milestone: milestone, overall: true)
        }
    }

    private static func checkOne(key: String, newCount: Int, fire: (Int) -> Void) {
        let oldCount = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(newCount, forKey: key)
        if let milestone = RideMilestone.crossed(oldCount: oldCount, newCount: newCount) {
            fire(milestone)
        }
    }
}

/// One consolidated morning notification — weather, crowd level, and today's top Must-Do pick —
/// instead of several separate banners. Fires at most once per (resort, calendar day), only
/// within an early-morning window, and only on a day the planned Trip actually covers this
/// resort. Driven from the foreground refresh (`ParkMapView`), same as the rain/heat heads-up —
/// not a true background-scheduled wake, so it needs the app opened once that morning.
enum MorningBriefing {
    static let windowHours = 6...10

    static func shouldFire(hour: Int, resort: String, tripResorts: [String], tripRange: ClosedRange<Date>?,
                           today: Date, calendar: Calendar = .current) -> Bool {
        guard windowHours.contains(hour), tripResorts.contains(resort), let tripRange else { return false }
        return tripRange.contains(calendar.startOfDay(for: today))
    }

    static func body(weather: String?, crowd: String?, mustDo: String?) -> String {
        let parts = [weather, crowd, mustDo].compactMap { $0 }
        return parts.isEmpty ? "Have a great day at the parks!" : parts.joined(separator: " · ")
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}

@MainActor
final class MorningBriefingService {
    static let shared = MorningBriefingService()
    private init() {}

    func checkAndFire(resort: ParkGroup, isWet: Bool, isHot: Bool, crowdLevel: CrowdLevel?,
                      mustDoPick: (name: String, wait: Int)?, trip: Trip?, now: Date = .now) {
        let hour = Calendar.current.component(.hour, from: now)
        guard MorningBriefing.shouldFire(hour: hour, resort: resort.rawValue, tripResorts: trip?.resortsRaw ?? [],
                                         tripRange: trip.map { $0.startDate...$0.endDate }, today: now) else { return }
        let key = "morningBriefingDay_\(resort.rawValue)"
        let dayKey = MorningBriefing.dayKey(now)
        guard UserDefaults.standard.string(forKey: key) != dayKey else { return }
        UserDefaults.standard.set(dayKey, forKey: key)
        let weather = isWet ? "Rain likely today" : (isHot ? "Hot today — plan indoor breaks" : nil)
        let crowd = crowdLevel.map { "\($0.rawValue) crowds expected" }
        let mustDo = mustDoPick.map { "Top pick: \($0.name) (~\($0.wait) min)" }
        NotificationService.shared.fireMorningBriefing(resort: resort, body: MorningBriefing.body(weather: weather, crowd: crowd, mustDo: mustDo))
    }
}

// MARK: - Keys

/// userInfo keys and category/action identifiers shared with `NotificationDelegate`.
enum NotificationKeys {
    static let rideId = "rideId"
    static let rideName = "rideName"
    static let parkName = "parkName"
    static let resort = "resort"
    static let postedWait = "postedWait"
    static let returnStart = "returnStart"
    static let passLabel = "passLabel"
    static let returnEnd = "returnEnd"

    static let aapWaitCategory = "WAIT_DROP_AAP"
    static let dasWaitCategory = "WAIT_DROP_DAS"
    static let llWatchCategory = "LL_WATCH_OPENING"
    static let loggedLightningLaneAction = "LOGGED_LIGHTNING_LANE"
    static let openBookingAppAction = "OPEN_BOOKING_APP"
    static let loggedReturnAction = "LOGGED_RETURN"
}

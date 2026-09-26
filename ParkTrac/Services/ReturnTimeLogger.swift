import Foundation
import SwiftData
import UIKit

// MARK: - Booking apps

/// Opens My Disney Experience / the Universal Orlando app for booking.
///
/// Neither app documents a URL scheme (guessed ones didn't work on device) and their
/// websites don't hand off to the apps, so we run the user's own Shortcut
/// ("Open Disney App" / "Open Universal App") when enabled in Settings → Booking Apps —
/// an "Open App" shortcut always works — and otherwise open the website.
enum BookingApp: String {
    case disney, universal

    var appName: String { self == .disney ? "My Disney Experience" : "Universal Orlando" }
    var shortcutName: String { self == .disney ? "Open Disney App" : "Open Universal App" }
    /// UserDefaults key for "use my Shortcut" (Settings → Booking Apps)
    var useShortcutKey: String { "bookingShortcut_\(rawValue)" }

    var websiteURL: URL {
        switch self {
        case .disney:    return URL(string: "https://disneyworld.disney.go.com/")!
        case .universal: return URL(string: "https://www.universalorlando.com/")!
        }
    }

    var shortcutURL: URL? {
        let name = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shortcutName
        return URL(string: "shortcuts://run-shortcut?name=\(name)")
    }

    @MainActor
    func open() {
        if UserDefaults.standard.bool(forKey: useShortcutKey), let url = shortcutURL {
            UIApplication.shared.open(url)
        } else {
            UIApplication.shared.open(websiteURL)
        }
    }
}


// MARK: - Access passes (Disney DAS / Universal AAP)

/// The disability access pass a guest holds at a resort. Both programs set the return
/// time from the ride's current standby wait (rules in `returnDelayMinutes`), and both are
/// booked only in the resort's
/// own app — ThrillTrack opens that app and logs the result, it never books itself.
enum AccessPass {
    case das   // Disney Disability Access Service
    case aap   // Universal Attraction Assistance Pass

    var label: String { self == .das ? "DAS" : "AAP" }
    var bookingAppName: String { self == .das ? "Disney App" : "Universal App" }
    var bookingApp: BookingApp { self == .das ? .disney : .universal }

    /// The pass this user holds at `resort` (same UserDefaults keys AppState writes).
    static func held(at resort: ParkGroup) -> AccessPass? {
        let ud = UserDefaults.standard
        switch resort {
        case .disney:    return ud.bool(forKey: "hasDAS") ? .das : nil
        case .universal: return ud.bool(forKey: "hasAAP") ? .aap : nil
        }
    }

    /// Minutes from booking until you may return, from the posted standby wait.
    func returnDelayMinutes(postedWait: Int?) -> Int {
        let wait = max(0, postedWait ?? 0)
        switch self {
        case .aap:
            // Universal AAP: under 30 min posted → return immediately;
            // 30+ → posted wait minus 15 min
            return wait < 30 ? 0 : wait - 15
        case .das:
            // Disney DAS: return time = posted standby wait (confirmed)
            return wait
        }
    }

    /// Return time if booked now.
    func estimatedReturn(postedWait: Int?, from now: Date = .now) -> Date {
        now.addingTimeInterval(TimeInterval(returnDelayMinutes(postedWait: postedWait) * 60))
    }

    /// "right away" or "around 2:35 PM" — for alert and ride-card copy.
    func returnPhrase(postedWait: Int?) -> String {
        returnDelayMinutes(postedWait: postedWait) == 0
            ? "right away"
            : "around \(estimatedReturn(postedWait: postedWait).formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Logger

/// Single place that records a booked return time: My Day item, Live Activity, reminder.
/// Used by BookReturnTimeSheet, the ride sheet's "I Booked It", and the notification action.
@MainActor
enum ReturnTimeLogger {
    /// - Parameters:
    ///   - isOpenEnded: DAS/AAP — usable any time after `returnStart` until park close.
    ///     Timed passes (Lightning Lane / Express Now) close at `returnEnd`.
    static func log(passLabel: String,
                    isOpenEnded: Bool,
                    rideId: String,
                    rideName: String,
                    parkName: String,
                    resort: String,
                    returnStart: Date,
                    returnEnd: Date,
                    context: ModelContext) {
        let item = PlanItem(
            title: rideName,
            kind: isOpenEnded ? "aap" : "ll",
            rideId: rideId,
            parkName: parkName,
            resort: resort
        )
        item.llReturnStart = returnStart
        item.llReturnEnd = isOpenEnded ? .distantFuture : returnEnd
        context.insert(item)
        try? context.save()

        let passId = "\(rideId)-\(Int(returnStart.timeIntervalSince1970))"
        if isOpenEnded {
            // Count down to when you can come back; after that it reads "valid until park close"
            LiveActivityManager.startReturnTime(
                passLabel: passLabel, rideName: rideName, parkName: parkName,
                returnEnd: returnStart > .now ? returnStart : nil)
            Task {
                await NotificationService.shared.requestAuthorization()
                NotificationService.shared.scheduleReturnReady(
                    passId: passId, passLabel: passLabel, rideName: rideName, at: returnStart)
            }
        } else {
            LiveActivityManager.startReturnTime(
                passLabel: passLabel, rideName: rideName, parkName: parkName, returnEnd: returnEnd)
            Task {
                await NotificationService.shared.requestAuthorization()
                NotificationService.shared.scheduleLLReminder(
                    passId: passId, rideName: rideName, returnEnd: returnEnd)
            }
        }
    }

    /// Lightning Lane Multi Pass booked at the return window ThrillTrack saw (ride card /
    /// notification action). Also stops that ride's watch — the user has their booking.
    static func logLightningLaneNow(rideId: String, rideName: String, parkName: String,
                                    returnStart: Date, returnEnd: Date?, context: ModelContext) {
        log(passLabel: "Lightning Lane", isOpenEnded: false, rideId: rideId, rideName: rideName,
            parkName: parkName, resort: ParkGroup.disney.rawValue, returnStart: returnStart,
            returnEnd: returnEnd ?? returnStart.addingTimeInterval(3600), context: context)
        LightningLaneWatchService.shared.remove(rideId: rideId)
    }

    /// DAS/AAP booked right now at the posted wait (ride sheet button / notification action).
    static func logAccessPassNow(_ pass: AccessPass, rideId: String, rideName: String, parkName: String,
                                 resort: ParkGroup, postedWait: Int?, context: ModelContext) -> Date {
        let returnStart = pass.estimatedReturn(postedWait: postedWait)
        log(passLabel: pass.label, isOpenEnded: true, rideId: rideId, rideName: rideName,
            parkName: parkName, resort: resort.rawValue, returnStart: returnStart,
            returnEnd: .distantFuture, context: context)
        return returnStart
    }
}

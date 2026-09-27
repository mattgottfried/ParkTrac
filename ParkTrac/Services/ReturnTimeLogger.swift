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
    case disney, universal, tokyoDisney, universalJapan

    static func `for`(_ resort: ParkGroup) -> BookingApp {
        switch resort {
        case .disney:         return .disney
        case .universal:      return .universal
        case .tokyoDisney:    return .tokyoDisney
        case .universalJapan: return .universalJapan
        }
    }

    var appName: String {
        switch self {
        case .disney:         return "My Disney Experience"
        case .universal:      return "Universal Orlando"
        case .tokyoDisney:    return "Tokyo Disney Resort App"
        case .universalJapan: return "Universal Studios Japan App"
        }
    }
    /// Button label, e.g. "Book in Disney App"
    var shortLabel: String {
        switch self {
        case .disney:         return "Disney App"
        case .universal:      return "Universal App"
        case .tokyoDisney:    return "Tokyo Disney App"
        case .universalJapan: return "USJ App"
        }
    }
    var shortcutName: String { "Open \(shortLabel)" }
    /// UserDefaults key for "use my Shortcut" (Settings → Booking Apps)
    var useShortcutKey: String { "bookingShortcut_\(rawValue)" }

    var websiteURL: URL {
        switch self {
        case .disney:         return URL(string: "https://disneyworld.disney.go.com/")!
        case .universal:      return URL(string: "https://www.universalorlando.com/")!
        case .tokyoDisney:    return URL(string: "https://www.tokyodisneyresort.jp/en/")!
        case .universalJapan: return URL(string: "https://www.usj.co.jp/web/en/us")!
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
        // Japan's access programs work differently (not modelled yet)
        case .tokyoDisney, .universalJapan: return nil
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

// MARK: - Area timed entry (USJ)

/// Super Nintendo World (and, on busy days, other areas) at Universal Studios Japan need an
/// Area Timed Entry ticket from the USJ app. ThrillTrack logs the window like a return pass:
/// My Day item, Live Activity, a reminder when it opens and 10 minutes before it closes.
enum AreaEntry {
    static let passLabel = "Timed Entry"
    static let presets = ["Super Nintendo World", "The Wizarding World of Harry Potter"]
    static let defaultWindowMinutes = 60

    static func isOffered(at resort: ParkGroup) -> Bool { resort == .universalJapan }

    /// Stable id for the plan item / notifications ("area-supernintendoworld").
    static func planId(for area: String) -> String { "area-" + RideMetadata.normalize(area) }

    /// Entry window; clamps silly lengths to 15 min … 4 h.
    static func window(start: Date, minutes: Int) -> (start: Date, end: Date) {
        let m = min(max(minutes, 15), 240)
        return (start, start.addingTimeInterval(TimeInterval(m * 60)))
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
                passLabel: passLabel, rideName: rideName, parkName: parkName, returnEnd: returnEnd,
                returnStart: returnStart)
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
                                    returnStart: Date, returnEnd: Date?,
                                    resort: ParkGroup = .disney, passLabel: String = "Lightning Lane",
                                    context: ModelContext) {
        log(passLabel: passLabel, isOpenEnded: false, rideId: rideId, rideName: rideName,
            parkName: parkName, resort: resort.rawValue, returnStart: returnStart,
            returnEnd: returnEnd ?? returnStart.addingTimeInterval(3600), context: context)
        LightningLaneWatchService.shared.remove(rideId: rideId)
    }

    /// Area Timed Entry window (USJ Super Nintendo World).
    static func logAreaEntry(area: String, start: Date, windowMinutes: Int,
                             resort: ParkGroup, context: ModelContext) {
        let name = area.trimmingCharacters(in: .whitespacesAndNewlines)
        let window = AreaEntry.window(start: start, minutes: windowMinutes)
        let id = AreaEntry.planId(for: name)
        log(passLabel: AreaEntry.passLabel, isOpenEnded: false, rideId: id, rideName: name,
            parkName: name, resort: resort.rawValue, returnStart: window.start,
            returnEnd: window.end, context: context)
        Task {
            await NotificationService.shared.requestAuthorization()
            NotificationService.shared.scheduleAreaEntryOpen(
                passId: "\(id)-\(Int(window.start.timeIntervalSince1970))",
                areaName: name, start: window.start, end: window.end)
        }
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

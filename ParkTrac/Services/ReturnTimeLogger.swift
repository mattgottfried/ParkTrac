import Foundation
import SwiftData

// MARK: - Access passes (Disney DAS / Universal AAP)

/// The disability access pass a guest holds at a resort. Both programs set the return
/// time from the ride's current standby wait, and both are booked only in the resort's
/// own app — ThrillTrack opens that app and logs the result, it never books itself.
enum AccessPass {
    case das   // Disney Disability Access Service
    case aap   // Universal Attraction Assistance Pass

    var label: String { self == .das ? "DAS" : "AAP" }
    var bookingAppName: String { self == .das ? "Disney App" : "Universal App" }

    /// Resort site; hands off to the official app when it's installed.
    var bookingURL: URL {
        switch self {
        case .das: return URL(string: "https://disneyworld.disney.go.com/")!
        case .aap: return URL(string: "https://www.universalorlando.com/")!
        }
    }

    /// The pass this user holds at `resort` (same UserDefaults keys AppState writes).
    static func held(at resort: ParkGroup) -> AccessPass? {
        let ud = UserDefaults.standard
        switch resort {
        case .disney:    return ud.bool(forKey: "hasDAS") ? .das : nil
        case .universal: return ud.bool(forKey: "hasAAP") ? .aap : nil
        }
    }

    /// Return time if booked now: current time + posted standby wait.
    static func estimatedReturn(postedWait: Int?, from now: Date = .now) -> Date {
        now.addingTimeInterval(TimeInterval(max(0, postedWait ?? 0) * 60))
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

    /// DAS/AAP booked right now at the posted wait (ride sheet button / notification action).
    static func logAccessPassNow(_ pass: AccessPass, rideId: String, rideName: String, parkName: String,
                                 resort: ParkGroup, postedWait: Int?, context: ModelContext) -> Date {
        let returnStart = AccessPass.estimatedReturn(postedWait: postedWait)
        log(passLabel: pass.label, isOpenEnded: true, rideId: rideId, rideName: rideName,
            parkName: parkName, resort: resort.rawValue, returnStart: returnStart,
            returnEnd: .distantFuture, context: context)
        return returnStart
    }
}

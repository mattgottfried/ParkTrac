import ActivityKit
import Foundation

/// Shared between the main app (starts/ends activities) and the widget
/// extension (renders them) — this file must be compiled into BOTH targets.
struct ThrillTrackActivityAttributes: ActivityAttributes {
    /// One stop on the Park Day timeline
    struct UpcomingStop: Codable, Hashable {
        var title: String
        var time: Date
        /// Expected wait for rides; nil for shows / dining / breaks
        var wait: Int?
        /// "ride" | "show" | "dining" | "break"
        var kind: String
    }

    enum Mode: String, Codable, Hashable {
        /// Lightning Lane / Express Now / DAS / AAP return window countdown
        case returnTime
        /// Posted-vs-actual wait stopwatch
        case waitTimer
        /// Dining reservation countdown
        case dining
        /// Park opening (rope drop) countdown
        case ropeDrop
        /// Next Lightning Lane booking eligibility (user-edited estimate)
        case nextBooking
        /// Today's live plan: the Next Up stop, updated after every wait-time refresh
        case parkDay
    }

    struct ContentState: Codable, Hashable {
        var countdownEnd: Date?   // returnTime/dining/ropeDrop/nextBooking: countdown target (nil = open-ended)
        var startedAt: Date?      // waitTimer: count-up origin
        var postedMinutes: Int?   // waitTimer: posted wait when timing started
        /// returnTime (timed passes): when the window opens — drives the progress bar
        var windowStart: Date? = nil

        // parkDay
        var stopTitle: String? = nil
        /// Expected wait at the next ride (nil for shows / dining)
        var stopWait: Int? = nil
        /// "Get in line ~2:15 PM · 6 min walk"
        var stopDetail: String? = nil
        /// "Then: Peter Pan's Flight (2:55 PM)"
        var thenText: String? = nil
        /// "4 of 9 done"
        var progressText: String? = nil
        /// "Rain likely 3–5 PM"
        var rainText: String? = nil
        /// Ride id of the next stop — the Done / Skip buttons act on it
        var stopRideId: String? = nil
        /// The next three stops for the timeline
        var upcoming: [UpcomingStop]? = nil
    }

    var mode: Mode
    var label: String     // e.g. "Lightning Lane", "Dining Reservation", "Rope Drop", "Next Booking", "Next Up"
    var title: String     // ride name / restaurant name / park name
    var subtitle: String  // park name / party-size info / empty
    /// Ride the activity is about (return time, stopwatch) — for its button
    var rideId: String? = nil
    /// `ParkGroup.rawValue` — picks the resort's colors
    var resortRaw: String? = nil
}

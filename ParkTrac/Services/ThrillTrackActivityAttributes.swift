import ActivityKit
import Foundation

/// Shared between the main app (starts/ends activities) and the widget
/// extension (renders them) — this file must be compiled into BOTH targets.
struct ThrillTrackActivityAttributes: ActivityAttributes {
    enum Mode: String, Codable, Hashable {
        /// Lightning Lane / Express Now / DAS / AAP return window countdown
        case returnTime
        /// Posted-vs-actual wait stopwatch
        case waitTimer
        /// Dining reservation countdown
        case dining
        /// Next Lightning Lane booking eligibility (user-edited estimate)
        case nextBooking
    }

    struct ContentState: Codable, Hashable {
        var countdownEnd: Date?   // returnTime/dining/nextBooking: countdown target (nil = open-ended)
        var startedAt: Date?      // waitTimer: count-up origin
        var postedMinutes: Int?   // waitTimer: posted wait when timing started
    }

    var mode: Mode
    var label: String     // e.g. "Lightning Lane", "Dining Reservation", "Next Booking"
    var title: String     // ride name / restaurant name / park name
    var subtitle: String  // park name / party-size info / empty
}

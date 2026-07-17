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
    }

    struct ContentState: Codable, Hashable {
        var returnEnd: Date?      // .returnTime: countdown target (nil = open-ended DAS/AAP)
        var startedAt: Date?      // .waitTimer: count-up origin
        var postedMinutes: Int?  // .waitTimer: posted wait when timing started
    }

    var mode: Mode
    var passLabel: String   // e.g. "Lightning Lane", "DAS", "Wait Timer"
    var rideName: String
    var parkName: String
}

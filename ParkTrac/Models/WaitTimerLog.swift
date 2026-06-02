import Foundation
import SwiftData

@Model final class WaitTimerLog {
    var rideId: String = ""
    var rideName: String = ""
    var resort: String = ""
    var postedMinutes: Int = 0
    var actualMinutes: Int = 0
    var startedAt: Date = Date()

    init(rideId: String, rideName: String, resort: String,
         postedMinutes: Int, actualMinutes: Int, startedAt: Date) {
        self.rideId = rideId
        self.rideName = rideName
        self.resort = resort
        self.postedMinutes = postedMinutes
        self.actualMinutes = actualMinutes
        self.startedAt = startedAt
    }
}

import Foundation
import SwiftData

@Model
final class DowntimeRecord {
    var rideId: String = ""
    var rideName: String = ""
    var parkId: String = ""
    var downStart: Date = Date()
    var downEnd: Date?

    var durationMinutes: Int? {
        guard let end = downEnd else { return nil }
        return Int(end.timeIntervalSince(downStart) / 60)
    }

    init(rideId: String, rideName: String, parkId: String, downStart: Date) {
        self.rideId = rideId
        self.rideName = rideName
        self.parkId = parkId
        self.downStart = downStart
        self.downEnd = nil
    }
}

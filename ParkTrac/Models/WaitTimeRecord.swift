import Foundation
import SwiftData

@Model
final class WaitTimeRecord {
    var rideId: String
    var rideName: String
    var parkId: String
    var recordedAt: Date
    var waitMinutes: Int?
    var status: String

    init(rideId: String, rideName: String, parkId: String, recordedAt: Date, waitMinutes: Int?, status: String) {
        self.rideId = rideId
        self.rideName = rideName
        self.parkId = parkId
        self.recordedAt = recordedAt
        self.waitMinutes = waitMinutes
        self.status = status
    }
}

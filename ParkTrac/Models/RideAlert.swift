import Foundation
import SwiftData

@Model final class RideAlert {
    var rideId: String = ""
    var rideName: String = ""
    var thresholdMinutes: Int = 0
    var isActive: Bool = true
    var createdAt: Date = Date()
    // Where the ride is, so the instant-alert server can watch it (nil on alerts made before 1.2)
    var parkId: String? = nil
    var parkName: String? = nil
    var resortRaw: String? = nil

    init(rideId: String, rideName: String, thresholdMinutes: Int,
         parkId: String? = nil, parkName: String? = nil, resort: ParkGroup? = nil) {
        self.rideId = rideId
        self.rideName = rideName
        self.thresholdMinutes = thresholdMinutes
        self.isActive = true
        self.createdAt = .now
        self.parkId = parkId
        self.parkName = parkName
        self.resortRaw = resort?.rawValue
    }
}

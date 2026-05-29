import Foundation
import SwiftData

@Model final class RideAlert {
    var rideId: String = ""
    var rideName: String = ""
    var thresholdMinutes: Int = 0
    var isActive: Bool = true
    var createdAt: Date = Date()

    init(rideId: String, rideName: String, thresholdMinutes: Int) {
        self.rideId = rideId
        self.rideName = rideName
        self.thresholdMinutes = thresholdMinutes
        self.isActive = true
        self.createdAt = .now
    }
}

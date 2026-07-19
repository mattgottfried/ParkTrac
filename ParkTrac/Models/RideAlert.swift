import Foundation
import SwiftData

@Model final class RideAlert {
    var id: UUID = UUID()
    var rideId: String = ""
    var rideName: String = ""
    var thresholdMinutes: Int = 0
    var isActive: Bool = true
    var createdAt: Date = Date()
    var syncUpdatedAt: Date = Date()

    init(rideId: String, rideName: String, thresholdMinutes: Int) {
        self.id = UUID()
        self.rideId = rideId
        self.rideName = rideName
        self.thresholdMinutes = thresholdMinutes
        self.isActive = true
        self.createdAt = .now
        self.syncUpdatedAt = .now
    }
}

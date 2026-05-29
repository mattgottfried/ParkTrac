import Foundation
import SwiftData

@Model
final class RideLog {
    var rideId: String = ""
    var rideName: String = ""
    var parkId: String = ""
    var parkName: String = ""
    var resort: String = ""
    var riddenAt: Date = Date()
    var waitMinutes: Int?
    var actualWaitMinutes: Int? = nil
    var notes: String = ""

    init(
        rideId: String,
        rideName: String,
        parkId: String,
        parkName: String,
        resort: String,
        riddenAt: Date = .now,
        waitMinutes: Int? = nil,
        actualWaitMinutes: Int? = nil,
        notes: String = ""
    ) {
        self.rideId             = rideId
        self.rideName           = rideName
        self.parkId             = parkId
        self.parkName           = parkName
        self.resort             = resort
        self.riddenAt           = riddenAt
        self.waitMinutes        = waitMinutes
        self.actualWaitMinutes  = actualWaitMinutes
        self.notes              = notes
    }
}

// MARK: - Visit Day helper (computed from RideLog entries)

struct VisitDay: Identifiable {
    let id: Date            // start of day
    let resort: String
    let entries: [RideLog]

    var parks: [String] { Array(Set(entries.map(\.parkName))).sorted() }
    var totalRides: Int  { entries.count }
}

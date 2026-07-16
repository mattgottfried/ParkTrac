import Foundation
import SwiftData

@Model final class VisitSaving {
    var date: Date = Date()
    var resort: String = ""
    var gateValue: Double = 0
    var note: String = ""
    // Parking the pass covered that day (0 / "" when not tracked).
    // Defaulted for CloudKit lightweight migration of existing records.
    var parkingValue: Double = 0
    var parkingType: String = ""  // "Standard" or "Valet"

    var totalValue: Double { gateValue + parkingValue }

    init(date: Date = .now, resort: String, gateValue: Double, note: String = "",
         parkingValue: Double = 0, parkingType: String = "") {
        self.date = date
        self.resort = resort
        self.gateValue = gateValue
        self.note = note
        self.parkingValue = parkingValue
        self.parkingType = parkingType
    }
}

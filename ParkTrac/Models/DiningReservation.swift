import Foundation
import SwiftData

@Model
final class DiningReservation {
    var id: UUID = UUID()
    var restaurantName: String = ""
    var resort: String = ""
    var date: Date = Date()          // combined date + time (use a single Date for both)
    var partySize: Int = 2
    var confirmationNumber: String = ""
    var notes: String = ""
    var isCompleted: Bool = false
    var syncUpdatedAt: Date = Date()

    init(
        restaurantName: String,
        resort: String,
        date: Date,
        partySize: Int = 2,
        confirmationNumber: String = "",
        notes: String = ""
    ) {
        self.id                 = UUID()
        self.restaurantName    = restaurantName
        self.resort            = resort
        self.date              = date
        self.partySize         = partySize
        self.confirmationNumber = confirmationNumber
        self.notes             = notes
        self.isCompleted       = false
        self.syncUpdatedAt     = Date()
    }
}

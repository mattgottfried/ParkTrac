import Foundation
import SwiftData

@Model
final class DiningReservation {
    var restaurantName: String = ""
    var resort: String = ""
    var date: Date = Date()          // combined date + time (use a single Date for both)
    var partySize: Int = 2
    var confirmationNumber: String = ""
    var notes: String = ""
    var isCompleted: Bool = false
    /// A mobile order pickup rather than a seated/table reservation — `date` is when it was
    /// placed (or when you'll place it), `pickupWindowEnd` is the app's pickup-by time.
    var isMobileOrder: Bool = false
    var pickupWindowEnd: Date? = nil

    init(
        restaurantName: String,
        resort: String,
        date: Date,
        partySize: Int = 2,
        confirmationNumber: String = "",
        notes: String = "",
        isMobileOrder: Bool = false,
        pickupWindowEnd: Date? = nil
    ) {
        self.restaurantName    = restaurantName
        self.resort            = resort
        self.date              = date
        self.partySize         = partySize
        self.confirmationNumber = confirmationNumber
        self.notes             = notes
        self.isCompleted       = false
        self.isMobileOrder     = isMobileOrder
        self.pickupWindowEnd   = pickupWindowEnd
    }
}

/// Minutes left in a mobile order's pickup window (pure).
enum MobileOrderCountdown {
    static func minutesRemaining(windowEnd: Date, now: Date = .now) -> Int? {
        let minutes = Int(windowEnd.timeIntervalSince(now) / 60)
        return minutes > 0 ? minutes : nil
    }
}

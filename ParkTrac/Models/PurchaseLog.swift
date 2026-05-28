import Foundation
import SwiftData

@Model final class PurchaseLog {
    var amount: Double
    var category: String  // "Food", "Merchandise", "Tickets", "Lightning Lane", "Other"
    var date: Date
    var resort: String
    var note: String

    init(amount: Double, category: String, resort: String, note: String = "") {
        self.amount = amount
        self.category = category
        self.date = .now
        self.resort = resort
        self.note = note
    }
}

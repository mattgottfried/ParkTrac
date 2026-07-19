import Foundation
import SwiftData

@Model final class PurchaseLog {
    var id: UUID = UUID()
    var amount: Double = 0
    var category: String = ""  // "Food", "Merchandise", "Tickets", "Lightning Lane", "Other"
    var date: Date = Date()
    var resort: String = ""
    var note: String = ""
    var isAPEligible: Bool = true  // counts toward AP discount savings calculation
    var syncUpdatedAt: Date = Date()

    init(amount: Double, category: String, resort: String, note: String = "", isAPEligible: Bool = true) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.date = .now
        self.resort = resort
        self.note = note
        self.isAPEligible = isAPEligible
        self.syncUpdatedAt = .now
    }
}

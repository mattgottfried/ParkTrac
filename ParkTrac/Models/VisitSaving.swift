import Foundation
import SwiftData

@Model final class VisitSaving {
    var date: Date = Date()
    var resort: String = ""
    var gateValue: Double = 0
    var note: String = ""

    init(date: Date = .now, resort: String, gateValue: Double, note: String = "") {
        self.date = date
        self.resort = resort
        self.gateValue = gateValue
        self.note = note
    }
}

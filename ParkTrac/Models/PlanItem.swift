import Foundation
import SwiftData

@Model final class PlanItem {
    var date: Date = Date()
    var scheduledTime: Date?
    var title: String = ""
    var kind: String = "note"   // "ride" | "show" | "dining" | "ll" | "note"
    var rideId: String?
    var parkName: String = ""
    var resort: String = ""
    var notes: String = ""
    var isDone: Bool = false
    var sortOrder: Int = 0
    var llReturnStart: Date?
    var llReturnEnd: Date?

    init(date: Date = Calendar.current.startOfDay(for: .now),
         scheduledTime: Date? = nil,
         title: String,
         kind: String = "note",
         rideId: String? = nil,
         parkName: String = "",
         resort: String = "",
         notes: String = "",
         sortOrder: Int = 0) {
        self.date = date
        self.scheduledTime = scheduledTime
        self.title = title
        self.kind = kind
        self.rideId = rideId
        self.parkName = parkName
        self.resort = resort
        self.notes = notes
        self.isDone = false
        self.sortOrder = sortOrder
    }
}

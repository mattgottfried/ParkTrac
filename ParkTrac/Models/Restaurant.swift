import Foundation
import SwiftData

@Model
final class Restaurant {
    var id: UUID = UUID()
    var name: String = ""
    var park: String = ""
    var dateVisited: Date = Date()
    var notes: String = ""
    var mattRating: Int = 3
    var wifeRating: Int = 3

    var averageRating: Double {
        Double(mattRating + wifeRating) / 2.0
    }

    init(
        name: String,
        park: String,
        dateVisited: Date = .now,
        notes: String = "",
        mattRating: Int = 3,
        wifeRating: Int = 3
    ) {
        self.id = UUID()
        self.name = name
        self.park = park
        self.dateVisited = dateVisited
        self.notes = notes
        self.mattRating = mattRating
        self.wifeRating = wifeRating
    }
}

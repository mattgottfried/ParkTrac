import Foundation
import SwiftData

@Model
final class BucketRestaurant {
    var id: UUID
    var name: String
    var park: String
    var resort: String
    var category: String
    var isVisited: Bool
    var visitDate: Date?
    var mattRating: Int
    var wifeRating: Int
    var notes: String
    var isFromAPI: Bool

    var averageRating: Double? {
        guard isVisited, mattRating > 0, wifeRating > 0 else { return nil }
        return Double(mattRating + wifeRating) / 2.0
    }

    init(
        name: String,
        park: String,
        resort: String,
        category: String,
        isFromAPI: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.park = park
        self.resort = resort
        self.category = category
        self.isVisited = false
        self.visitDate = nil
        self.mattRating = 0
        self.wifeRating = 0
        self.notes = ""
        self.isFromAPI = isFromAPI
    }
}

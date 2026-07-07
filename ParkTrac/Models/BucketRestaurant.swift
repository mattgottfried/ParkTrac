import Foundation
import SwiftData

@Model
final class BucketRestaurant {
    var id: UUID = UUID()
    var name: String = ""
    var park: String = ""
    var resort: String = ""
    var category: String = ""
    var isVisited: Bool = false
    var visitDate: Date?
    var mattRating: Double = 0
    var wifeRating: Double = 0
    var notes: String = ""
    var isFromAPI: Bool = false
    @Attribute(.externalStorage) var photoData: [Data] = []

    var averageRating: Double? {
        guard isVisited, mattRating > 0, wifeRating > 0 else { return nil }
        return (mattRating + wifeRating) / 2.0
    }

    init(
        name: String,
        park: String,
        resort: String,
        category: String,
        isVisited: Bool = false,
        mattRating: Double = 0,
        wifeRating: Double = 0,
        isFromAPI: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.park = park
        self.resort = resort
        self.category = category
        self.isVisited = isVisited
        self.visitDate = nil
        self.mattRating = mattRating
        self.wifeRating = wifeRating
        self.notes = ""
        self.isFromAPI = isFromAPI
        self.photoData = []
    }
}

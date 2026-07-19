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
    var syncUpdatedAt: Date = Date()
    @Attribute(.externalStorage) var photoData: [Data] = []

    // mattRating/wifeRating stay declared (unused by app logic) so RatingMigrationService
    // has legacy data to read once; real ratings now live in RestaurantRating rows.
    var averageRating: Double? {
        guard isVisited, let context = modelContext else { return nil }
        let rid = id
        let ratings = (try? context.fetch(FetchDescriptor<RestaurantRating>(
            predicate: #Predicate { $0.restaurantId == rid }
        ))) ?? []
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.map(\.stars).reduce(0, +)) / Double(ratings.count)
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
        self.syncUpdatedAt = Date()
        self.photoData = []
    }
}

import Foundation
import SwiftData

/// One guest's star rating on one bucket-list restaurant. Kept as its own row (rather
/// than a ratings blob on BucketRestaurant) so different guests' ratings never conflict
/// during household sync — each row is its own CKRecord.
@Model
final class RestaurantRating {
    var id: UUID = UUID()
    var restaurantId: UUID = UUID()
    var guestId: UUID = UUID()
    var stars: Int = 0
    var syncUpdatedAt: Date = Date()

    init(restaurantId: UUID, guestId: UUID, stars: Int) {
        self.id = UUID()
        self.restaurantId = restaurantId
        self.guestId = guestId
        self.stars = stars
        self.syncUpdatedAt = .now
    }

    static func current(restaurantId: UUID, guestId: UUID, context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<RestaurantRating>(predicate: #Predicate {
            $0.restaurantId == restaurantId && $0.guestId == guestId
        })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.stars ?? 0
    }

    static func set(restaurantId: UUID, guestId: UUID, stars: Int, context: ModelContext) {
        var descriptor = FetchDescriptor<RestaurantRating>(predicate: #Predicate {
            $0.restaurantId == restaurantId && $0.guestId == guestId
        })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            if stars <= 0 {
                context.delete(existing)
            } else if existing.stars != stars {
                existing.stars = stars
            }
        } else if stars > 0 {
            context.insert(RestaurantRating(restaurantId: restaurantId, guestId: guestId, stars: stars))
        }
    }

    static func deleteAll(restaurantId: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<RestaurantRating>(predicate: #Predicate { $0.restaurantId == restaurantId })
        for row in (try? context.fetch(descriptor)) ?? [] {
            context.delete(row)
        }
    }
}

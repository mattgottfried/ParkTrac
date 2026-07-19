import Foundation
import SwiftData

/// One guest's star rating on one bucket-list hotel. See RestaurantRating for why this
/// is its own row rather than a ratings blob on HotelStay.
@Model
final class HotelRating {
    var id: UUID = UUID()
    var hotelId: UUID = UUID()
    var guestId: UUID = UUID()
    var stars: Int = 0
    var syncUpdatedAt: Date = Date()

    init(hotelId: UUID, guestId: UUID, stars: Int) {
        self.id = UUID()
        self.hotelId = hotelId
        self.guestId = guestId
        self.stars = stars
        self.syncUpdatedAt = .now
    }

    static func current(hotelId: UUID, guestId: UUID, context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<HotelRating>(predicate: #Predicate {
            $0.hotelId == hotelId && $0.guestId == guestId
        })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.stars ?? 0
    }

    static func set(hotelId: UUID, guestId: UUID, stars: Int, context: ModelContext) {
        var descriptor = FetchDescriptor<HotelRating>(predicate: #Predicate {
            $0.hotelId == hotelId && $0.guestId == guestId
        })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            if stars <= 0 {
                context.delete(existing)
            } else if existing.stars != stars {
                existing.stars = stars
            }
        } else if stars > 0 {
            context.insert(HotelRating(hotelId: hotelId, guestId: guestId, stars: stars))
        }
    }

    static func deleteAll(hotelId: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<HotelRating>(predicate: #Predicate { $0.hotelId == hotelId })
        for row in (try? context.fetch(descriptor)) ?? [] {
            context.delete(row)
        }
    }
}

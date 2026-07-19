import Foundation
import SwiftData

/// One-time migration from the old hardcoded mattRating/wifeRating fields on
/// BucketRestaurant/HotelStay to per-guest RestaurantRating/HotelRating rows. Only runs
/// (and only creates bootstrap Guests) if legacy non-zero ratings actually exist — a
/// fresh install has nothing to migrate and never touches this at all, so no phantom
/// "Matt"/"Heather" guests get created for new users.
actor RatingMigrationService {
    static let shared = RatingMigrationService()
    private static let migratedKey = "hasMigratedGuestRatings_v1"

    @MainActor
    func migrateIfNeeded(context: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: Self.migratedKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: Self.migratedKey) }

        let restaurants = (try? context.fetch(FetchDescriptor<BucketRestaurant>())) ?? []
        let hotels = (try? context.fetch(FetchDescriptor<HotelStay>())) ?? []
        let hasLegacyData = restaurants.contains { $0.mattRating > 0 || $0.wifeRating > 0 }
            || hotels.contains { $0.mattRating > 0 || $0.wifeRating > 0 }
        guard hasLegacyData else { return }

        let partyMembers = UserDefaults.standard.stringArray(forKey: "partyMembers") ?? []
        let firstName = partyMembers.first ?? "Matt"
        let secondName = partyMembers.count > 1 ? partyMembers[1] : "Heather"
        let mattGuest = findOrCreateGuest(named: firstName, context: context)
        let heatherGuest = findOrCreateGuest(named: secondName, context: context)

        for restaurant in restaurants {
            if restaurant.mattRating > 0 {
                RestaurantRating.set(restaurantId: restaurant.id, guestId: mattGuest.id,
                                      stars: Int(restaurant.mattRating.rounded()), context: context)
            }
            if restaurant.wifeRating > 0 {
                RestaurantRating.set(restaurantId: restaurant.id, guestId: heatherGuest.id,
                                      stars: Int(restaurant.wifeRating.rounded()), context: context)
            }
        }
        for hotel in hotels {
            if hotel.mattRating > 0 {
                HotelRating.set(hotelId: hotel.id, guestId: mattGuest.id, stars: hotel.mattRating, context: context)
            }
            if hotel.wifeRating > 0 {
                HotelRating.set(hotelId: hotel.id, guestId: heatherGuest.id, stars: hotel.wifeRating, context: context)
            }
        }
        try? context.save()
    }

    @MainActor
    private func findOrCreateGuest(named name: String, context: ModelContext) -> Guest {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = ((try? context.fetch(FetchDescriptor<Guest>())) ?? [])
            .first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let guest = Guest(name: trimmed)
        context.insert(guest)
        return guest
    }

    // MARK: - Cross-device duplicate cleanup

    /// Merges Guest rows that only exist as duplicates because two devices each ran
    /// migrateIfNeeded independently before joining a household together (migratedKey is
    /// a local UserDefaults flag, not synced, so each device bootstraps its own "Matt"/
    /// "Heather"/etc. guest with its own UUID — household sync then merges both as
    /// genuinely separate records, since Guest sync is ID-based with no name matching).
    /// Runs every launch; cheap no-op once converged. Keeps the guest with the
    /// lexicographically smallest UUID string — an arbitrary but deterministic tie-break
    /// so every device picks the same survivor instead of fighting over which to delete.
    @MainActor
    func dedupeGuestsIfNeeded(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Guest>())) ?? []
        let groups = Dictionary(grouping: all) { $0.name.trimmingCharacters(in: .whitespaces).lowercased() }
        for (_, duplicates) in groups where duplicates.count > 1 {
            let sorted = duplicates.sorted { $0.id.uuidString < $1.id.uuidString }
            let keeper = sorted[0]
            for guest in sorted.dropFirst() {
                repointRestaurantRatings(from: guest.id, to: keeper.id, context: context)
                repointHotelRatings(from: guest.id, to: keeper.id, context: context)
                context.delete(guest)
            }
        }
        try? context.save()
    }

    @MainActor
    private func repointRestaurantRatings(from oldGuestId: UUID, to newGuestId: UUID, context: ModelContext) {
        let old = (try? context.fetch(FetchDescriptor<RestaurantRating>(
            predicate: #Predicate { $0.guestId == oldGuestId }
        ))) ?? []
        for rating in old {
            let restaurantId = rating.restaurantId
            let keeperAlreadyRated = ((try? context.fetch(FetchDescriptor<RestaurantRating>(
                predicate: #Predicate { $0.restaurantId == restaurantId && $0.guestId == newGuestId }
            ))) ?? []).first != nil
            if keeperAlreadyRated {
                context.delete(rating)
            } else {
                rating.guestId = newGuestId
            }
        }
    }

    @MainActor
    private func repointHotelRatings(from oldGuestId: UUID, to newGuestId: UUID, context: ModelContext) {
        let old = (try? context.fetch(FetchDescriptor<HotelRating>(
            predicate: #Predicate { $0.guestId == oldGuestId }
        ))) ?? []
        for rating in old {
            let hotelId = rating.hotelId
            let keeperAlreadyRated = ((try? context.fetch(FetchDescriptor<HotelRating>(
                predicate: #Predicate { $0.hotelId == hotelId && $0.guestId == newGuestId }
            ))) ?? []).first != nil
            if keeperAlreadyRated {
                context.delete(rating)
            } else {
                rating.guestId = newGuestId
            }
        }
    }
}

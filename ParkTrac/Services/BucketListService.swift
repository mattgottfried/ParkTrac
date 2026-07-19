import Foundation
import SwiftData

actor BucketListService {
    static let shared = BucketListService()

    // Seeds restaurants and hotels into SwiftData on first launch.
    // Skips entries that already exist (matched by name + park).
    @MainActor
    func seedIfNeeded(context: ModelContext) async {
        await seedRestaurants(context: context)
        await seedHotels(context: context)
        // Seeding's dedup check races against SwiftData's CloudKit initial import on a
        // fresh install: this device's local fetch can miss rows that were seeded on a
        // previous install and are still mid-download, so it reseeds them, then the
        // download lands moments later — same restaurant/hotel now twice. Cheap to check
        // and self-heals every launch, so it's simpler than trying to detect "CloudKit's
        // initial sync has finished."
        dedupeRestaurants(context: context)
        dedupeHotels(context: context)
    }

    @MainActor
    private func seedRestaurants(context: ModelContext) async {
        let existing = (try? context.fetch(FetchDescriptor<BucketRestaurant>())) ?? []
        let existingKeys = Set(existing.map { "\($0.name)|\($0.park)" })

        for seed in allSeedRestaurants {
            let key = "\(seed.name)|\(seed.park)"
            guard !existingKeys.contains(key) else { continue }
            // Seed only the catalog (name/park/resort/category) — visited status and
            // ratings are personal data and must start blank for every install, not
            // pre-filled from whatever the seed data happens to contain.
            let restaurant = BucketRestaurant(
                name: seed.name,
                park: seed.park,
                resort: seed.resort,
                category: seed.category
            )
            context.insert(restaurant)
        }

        try? context.save()
    }

    @MainActor
    private func seedHotels(context: ModelContext) async {
        let existing = (try? context.fetch(FetchDescriptor<HotelStay>())) ?? []
        let existingNames = Set(existing.map(\.hotelName))

        for seed in allSeedHotels {
            guard !existingNames.contains(seed.name) else { continue }
            let hotel = HotelStay(
                hotelName: seed.name,
                resort: seed.resort,
                tier: seed.tier
            )
            context.insert(hotel)
        }

        try? context.save()
    }

    // Merges duplicate BucketRestaurant rows (same name + park) that can arise from the
    // seed/CloudKit-import race described in seedIfNeeded. Keeps whichever duplicate has
    // the most user signal (visited, rated, noted, photographed) and deletes the rest.
    @MainActor
    private func dedupeRestaurants(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BucketRestaurant>())) ?? []
        let groups = Dictionary(grouping: all) { "\($0.name)|\($0.park)" }
        for (_, duplicates) in groups where duplicates.count > 1 {
            let keeper = duplicates.max { score($0, context: context) < score($1, context: context) }
            for restaurant in duplicates where restaurant !== keeper {
                context.delete(restaurant)
            }
        }
        try? context.save()
    }

    @MainActor
    private func score(_ r: BucketRestaurant, context: ModelContext) -> Int {
        let rid = r.id
        let hasRatings = !((try? context.fetch(FetchDescriptor<RestaurantRating>(
            predicate: #Predicate { $0.restaurantId == rid }
        ))) ?? []).isEmpty
        return (r.isVisited ? 1000 : 0) + (hasRatings ? 100 : 0)
            + (r.notes.isEmpty ? 0 : 10) + r.photoData.count
    }

    // Same idea as dedupeRestaurants, for HotelStay (keyed by hotelName, matching
    // seedHotels' own dedup key).
    @MainActor
    private func dedupeHotels(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<HotelStay>())) ?? []
        let groups = Dictionary(grouping: all, by: \.hotelName)
        for (_, duplicates) in groups where duplicates.count > 1 {
            let keeper = duplicates.max { score($0, context: context) < score($1, context: context) }
            for hotel in duplicates where hotel !== keeper {
                context.delete(hotel)
            }
        }
        try? context.save()
    }

    @MainActor
    private func score(_ h: HotelStay, context: ModelContext) -> Int {
        let hid = h.id
        let hasRatings = !((try? context.fetch(FetchDescriptor<HotelRating>(
            predicate: #Predicate { $0.hotelId == hid }
        ))) ?? []).isEmpty
        return (h.isVisited ? 1000 : 0) + (hasRatings ? 100 : 0)
            + (h.notes.isEmpty ? 0 : 10) + h.photoData.count
    }

    // Attempts to fetch additional restaurants from ThemeParks.wiki API
    // and merge them in alongside the seed data.
    @MainActor
    func fetchAndMergeAPIRestaurants(parkId: String, parkName: String, resort: String, context: ModelContext) async {
        guard let entries = try? await ParkAPIService.shared.fetchAttractionChildren(parkId: parkId) else { return }
        let diningEntries = entries.filter { $0.entityType == "RESTAURANT" || $0.entityType == "DINING" }

        let existing = (try? context.fetch(FetchDescriptor<BucketRestaurant>())) ?? []
        let existingKeys = Set(existing.map { "\($0.name)|\($0.park)" })

        for entry in diningEntries {
            let key = "\(entry.name)|\(parkName)"
            guard !existingKeys.contains(key) else { continue }
            let restaurant = BucketRestaurant(
                name: entry.name,
                park: parkName,
                resort: resort,
                category: "Quick Service",
                isFromAPI: true
            )
            context.insert(restaurant)
        }

        try? context.save()
    }
}

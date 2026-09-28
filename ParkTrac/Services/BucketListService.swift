import Foundation
import SwiftData

actor BucketListService {
    static let shared = BucketListService()

    /// Restaurants that have permanently closed in real life (Sept 2026), keyed "name|park".
    /// `markClosedRestaurants` sets `isClosed` on any existing row rather than deleting it, so a
    /// guest's rating/notes/photos on a since-closed restaurant are never lost — the row just
    /// shows a CLOSED banner. New installs don't get these seeded at all (removed from
    /// `allSeedRestaurants`), so this only ever affects installs that had them already.
    static let closedRestaurantKeys: Set<String> = [
        "Wolfgang Puck Bar & Grill|Disney Springs",
        "Thunder Falls Terrace|Islands of Adventure",
        // Hot Dog Hall of Fame® closed and was replaced by a different restaurant (Fat One's
        // Hot Dogs & Italian Ice) in the same spot — not a rename, so the old one is marked
        // closed rather than renamed, and Fat One's is seeded separately.
        "Hot Dog Hall of Fame®|CityWalk",
    ]

    // Seeds restaurants and hotels into SwiftData on first launch.
    // Skips entries that already exist (matched by name + park).
    @MainActor
    func seedIfNeeded(context: ModelContext) async {
        await markClosedRestaurants(context: context)
        await seedRestaurants(context: context)
        await seedHotels(context: context)
        await seedCharacters(context: context)
    }

    @MainActor
    private func markClosedRestaurants(context: ModelContext) async {
        let existing = (try? context.fetch(FetchDescriptor<BucketRestaurant>())) ?? []
        for restaurant in existing {
            let key = "\(restaurant.name)|\(restaurant.park)"
            if Self.closedRestaurantKeys.contains(key), !restaurant.isClosed {
                restaurant.isClosed = true
            }
        }
        try? context.save()
    }

    @MainActor
    private func seedRestaurants(context: ModelContext) async {
        let existing = (try? context.fetch(FetchDescriptor<BucketRestaurant>())) ?? []
        let existingKeys = Set(existing.map { "\($0.name)|\($0.park)" })

        for seed in allSeedRestaurants {
            let key = "\(seed.name)|\(seed.park)"
            guard !existingKeys.contains(key) else { continue }
            // Catalog only. SeedData's isVisited / ratings are Matt & Heather's personal
            // history, kept in the file for reference — never import them, or every new
            // install (any Apple ID) would start with their visits and stats.
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

    @MainActor
    private func seedCharacters(context: ModelContext) async {
        let existing = (try? context.fetch(FetchDescriptor<CharacterMeet>())) ?? []
        let existingKeys = Set(existing.map { "\($0.character)|\($0.park)" })

        for seed in allCharacterAppearances {
            let key = "\(seed.character)|\(seed.park)"
            guard !existingKeys.contains(key) else { continue }
            let meet = CharacterMeet(character: seed.character, park: seed.park, resort: seed.resort, location: seed.location)
            context.insert(meet)
        }

        try? context.save()
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

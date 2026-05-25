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
    }

    @MainActor
    private func seedRestaurants(context: ModelContext) async {
        let existing = (try? context.fetch(FetchDescriptor<BucketRestaurant>())) ?? []
        let existingKeys = Set(existing.map { "\($0.name)|\($0.park)" })

        for seed in seedRestaurants {
            let key = "\(seed.name)|\(seed.park)"
            guard !existingKeys.contains(key) else { continue }
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

        for seed in seedHotels {
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

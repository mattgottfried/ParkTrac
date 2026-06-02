import Foundation
import SwiftData

struct DiningSeedService {
    static func seedIfNeeded(context: ModelContext) throws {
        let descriptor = FetchDescriptor<Restaurant>()
        let existing = try context.fetch(descriptor)
        guard existing.isEmpty else { return }

        for entry in visitedRestaurants {
            let r = Restaurant(
                name: entry.name,
                park: entry.park,
                mattRating: entry.matt,
                wifeRating: entry.heather
            )
            context.insert(r)
        }
        try context.save()
    }
}

private struct VisitedEntry {
    let name: String
    let park: String
    let heather: Int
    let matt: Int
}

private let visitedRestaurants: [VisitedEntry] = [
    VisitedEntry(name: "50's Prime Time Café", park: "Disney's Hollywood Studios", heather: 5, matt: 4),
    VisitedEntry(name: "ABC Commissary", park: "Disney's Hollywood Studios", heather: 3, matt: 1),
    VisitedEntry(name: "Backlot Express", park: "Disney's Hollywood Studios", heather: 3, matt: 3),
    VisitedEntry(name: "Be Our Guest Restaurant", park: "Magic Kingdom Park", heather: 5, matt: 4),
    VisitedEntry(name: "Biergarten Restaurant", park: "EPCOT", heather: 5, matt: 5),
    VisitedEntry(name: "Blaze Fast-Fire'd Pizza", park: "Disney Springs", heather: 1, matt: 1),
    VisitedEntry(name: "Boma - Flavors of Africa", park: "Disney's Animal Kingdom Lodge", heather: 5, matt: 5),
    VisitedEntry(name: "Chef Mickey's", park: "Disney's Contemporary Resort", heather: 2, matt: 3),
    VisitedEntry(name: "Chefs de France", park: "EPCOT", heather: 5, matt: 4),
    VisitedEntry(name: "Chicken Guy!", park: "Disney Springs", heather: 3, matt: 3),
    VisitedEntry(name: "Columbia Harbour House", park: "Magic Kingdom Park", heather: 5, matt: 4),
    VisitedEntry(name: "Cosmic Ray's Starlight Café", park: "Magic Kingdom Park", heather: 4, matt: 4),
    VisitedEntry(name: "D-Luxe Burger", park: "Disney Springs", heather: 1, matt: 1),
    VisitedEntry(name: "Docking Bay 7 Food and Cargo", park: "Disney's Hollywood Studios", heather: 2, matt: 3),
    VisitedEntry(name: "Flame Tree Barbecue", park: "Disney's Animal Kingdom Theme Park", heather: 4, matt: 3),
    VisitedEntry(name: "Hoop-Dee-Doo Musical Revue", park: "The Campsites at Disney's Fort Wilderness Resort", heather: 5, matt: 4),
    VisitedEntry(name: "Jiko - The Cooking Place", park: "Disney's Animal Kingdom Lodge", heather: 5, matt: 5),
    VisitedEntry(name: "Jungle Navigation Co. LTD Skipper Canteen", park: "Magic Kingdom Park", heather: 3, matt: 4),
    VisitedEntry(name: "Kona Cafe", park: "Disney's Polynesian Village Resort", heather: 3, matt: 3),
    VisitedEntry(name: "Les Halles Boulangerie-Patisserie", park: "EPCOT", heather: 4, matt: 4),
    VisitedEntry(name: "Liberty Tree Tavern", park: "Magic Kingdom Park", heather: 5, matt: 5),
    VisitedEntry(name: "Mama Melrose's Ristorante Italiano", park: "Disney's Hollywood Studios", heather: 3, matt: 2),
    VisitedEntry(name: "Morimoto Asia", park: "Disney Springs", heather: 5, matt: 5),
    VisitedEntry(name: "Nine Dragons Restaurant", park: "EPCOT", heather: 1, matt: 1),
    VisitedEntry(name: "Olivia's Cafe", park: "Disney's Old Key West Resort", heather: 5, matt: 3),
    VisitedEntry(name: "Pecos Bill Tall Tale Inn and Cafe", park: "Magic Kingdom Park", heather: 2, matt: 2),
    VisitedEntry(name: "PizzeRizzo", park: "Disney's Hollywood Studios", heather: 4, matt: 5),
    VisitedEntry(name: "Planet Hollywood", park: "Disney Springs", heather: 5, matt: 5),
    VisitedEntry(name: "Rainforest Cafe", park: "Disney Springs", heather: 5, matt: 5),
    VisitedEntry(name: "Regal Eagle Smokehouse: Craft Drafts & Barbecue", park: "EPCOT", heather: 5, matt: 4),
    VisitedEntry(name: "Restaurantosaurus", park: "Disney's Animal Kingdom Theme Park", heather: 5, matt: 5),
    VisitedEntry(name: "Rose & Crown Dining Room", park: "EPCOT", heather: 5, matt: 5),
    VisitedEntry(name: "Roundup Rodeo BBQ", park: "Disney's Hollywood Studios", heather: 3, matt: 3),
    VisitedEntry(name: "Satu'li Canteen", park: "Disney's Animal Kingdom Theme Park", heather: 4, matt: 5),
    VisitedEntry(name: "Sci-Fi Dine-Inn Theater Restaurant", park: "Disney's Hollywood Studios", heather: 2, matt: 3),
    VisitedEntry(name: "Sleepy Hollow", park: "Magic Kingdom Park", heather: 2, matt: 3),
    VisitedEntry(name: "T-Rex", park: "Disney Springs", heather: 4, matt: 5),
    VisitedEntry(name: "Teppan Edo", park: "EPCOT", heather: 1, matt: 2),
    VisitedEntry(name: "The BOATHOUSE", park: "Disney Springs", heather: 5, matt: 4),
    VisitedEntry(name: "The Edison", park: "Disney Springs", heather: 3, matt: 3),
    VisitedEntry(name: "The Friar's Nook", park: "Magic Kingdom Park", heather: 5, matt: 3),
    VisitedEntry(name: "The Lunching Pad", park: "Magic Kingdom Park", heather: 1, matt: 2),
    VisitedEntry(name: "The Polite Pig", park: "Disney Springs", heather: 4, matt: 4),
    VisitedEntry(name: "Tortuga Tavern", park: "Magic Kingdom Park", heather: 3, matt: 3),
    VisitedEntry(name: "Via Napoli Ristorante e Pizzeria", park: "EPCOT", heather: 5, matt: 5),
    VisitedEntry(name: "Yak & Yeti™ Restaurant", park: "Disney's Animal Kingdom Theme Park", heather: 5, matt: 5),
    VisitedEntry(name: "Yorkshire County Fish Shop", park: "EPCOT", heather: 5, matt: 2),
]

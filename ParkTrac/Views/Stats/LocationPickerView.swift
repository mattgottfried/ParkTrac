import SwiftUI

// MARK: - Location data

private let disneyMerchLocations: [String: [String]] = [
    "Magic Kingdom": [
        "The Emporium", "Uptown Jewelers", "Yankee Trader", "Memento Mori",
        "Star Traders", "Tomorrowland Light & Power Co.", "Fantasyland shops",
        "Frontier Trading Post", "Ye Olde Christmas Shoppe"
    ],
    "EPCOT": [
        "MouseGear", "Pin Central", "World Traveler",
        "Canada — Northwest Mercantile", "China — Yong Feng Shangdian",
        "France — Plume et Palette", "Germany — Der Teddybär", "Italy — Il Bel Cristallo",
        "Japan — Mitsukoshi", "Mexico — La Princesa de Cristal",
        "Morocco — Casablanca Carpets", "Norway — The Puffin's Roost",
        "United Kingdom — The Crown & Crest"
    ],
    "Hollywood Studios": [
        "Keystone Clothiers", "Once Upon a Time", "Celebrity 5 & 10",
        "Indiana Jones Adventure Outpost", "Tatooine Traders",
        "Dok-Ondar's Den of Antiquities", "The Creature Stall", "Elias & Co."
    ],
    "Animal Kingdom": [
        "Island Mercantile", "Bhaktapur Market", "Chester & Hester's",
        "Windtraders", "Mombasa Marketplace", "Serka Zong Bazaar",
        "Pongu Pongu (merchandise only)"
    ],
    "Disney Springs": [
        "World of Disney", "Disney Style", "Basin White", "Chapel Hats",
        "Curl by Sammy Duvall", "LEGO Store", "Marketplace Co-Op",
        "Rainforest Cafe Gift Shop", "Splitsville (merchandise)", "Star Wars Galactic Outpost",
        "The Art of Disney", "Twenty Eight & Main"
    ],
    "Grand Floridian Resort": ["Summer Lace", "Boulangerie Patisserie"],
    "Wilderness Lodge": ["Wilderness Lodge Mercantile"],
    "Polynesian Village Resort": ["Trader Jack's"],
    "Beach Club Resort": ["Beachclub Marketplace"],
    "BoardWalk": ["Screen Door General Store"],
    "Saratoga Springs Resort": ["Saratoga Springs gift shop"],
    "Animal Kingdom Lodge": ["Zawadi Marketplace"],
    "Caribbean Beach Resort": ["Calypso Trading Post"],
    "Contemporary Resort": ["Contemporary resort shop"],
    "Port Orleans Riverside": ["Fulton's General Store"],
    "Coronado Springs": ["Panchito's Gifts & Sundries"],
]

private let universalMerchLocations: [String: [String]] = [
    "Universal Studios Florida": [
        "Universal Studios Store", "Universal Studios Gear", "Minion Mart",
        "Super Silly Stuff", "ET's Toy Closet", "Hello Kitty",
        "Weasleys' Wizard Wheezes", "Magical Menagerie", "Dervish and Banges",
        "The Simpsons store", "Revenge of the Mummy gift shop"
    ],
    "Islands of Adventure": [
        "Islands of Adventure Trading Company", "Marvel Alterniverse Store",
        "Jurassic Outfitters", "Dervish and Banges (IOA)", "Filch's Emporium",
        "Skull Kingdom", "Cats, Hats & Things", "Mulberry Street Store"
    ],
    "Epic Universe": [
        "Epic Universe main shops", "Ministry of Magic gift shop",
        "Nintendo gift shop", "How to Train Your Dragon gift shop",
        "Universal Monsters gift shop", "Celestial Park shops"
    ],
    "CityWalk": [
        "Universal Studios Store at CityWalk", "Fossil", "Quiet Flight",
        "Endangered Species Store", "Hart & Huntington Tattoo"
    ],
    "Portofino Bay Hotel": ["Portofino Bay shops"],
    "Hard Rock Hotel": ["Hard Rock Hotel gift shop"],
    "Royal Pacific Resort": ["Royal Pacific gift shop"],
    "Sapphire Falls Resort": ["Sapphire Falls gift shop"],
    "Cabana Bay Beach Resort": ["Cabana Bay gift shop"],
]

// MARK: - Picker view

struct LocationPickerView: View {
    let resort: String
    let category: String
    @Binding var selectedPark: String
    @Binding var selectedLocation: String
    @Binding var isAPEligible: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var drillPark: String? = nil
    @State private var searchText = ""

    private var isDisney: Bool { resort == ParkGroup.disney.rawValue }

    // MARK: Parks

    private var parks: [String] {
        if category == "Food" {
            let restaurants = allSeedRestaurants.filter { $0.resort == resort }
            return Array(Set(restaurants.map(\.park))).sorted()
        } else if category == "Merchandise" {
            let dict = isDisney ? disneyMerchLocations : universalMerchLocations
            return Array(dict.keys).sorted()
        } else {
            // Generic park list
            return isDisney
                ? ["Magic Kingdom", "EPCOT", "Hollywood Studios", "Animal Kingdom",
                   "Disney Springs", "Resort Hotels", "BoardWalk"]
                : ["Universal Studios Florida", "Islands of Adventure", "Epic Universe",
                   "CityWalk", "Resort Hotels"]
        }
    }

    // MARK: Locations for a park

    private func locations(for park: String) -> [String] {
        if category == "Food" {
            let base = allSeedRestaurants
                .filter { $0.resort == resort && $0.park == park }
                .map(\.name)
                .sorted()
            return ["Outdoor Cart / Quick Grab"] + base
        } else if category == "Merchandise" {
            let dict = isDisney ? disneyMerchLocations : universalMerchLocations
            return dict[park] ?? []
        } else {
            return []
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if let park = drillPark {
                    locationList(for: park)
                } else {
                    parkList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if drillPark != nil {
                        Button("Back") { drillPark = nil }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var parkList: some View {
        List(parks, id: \.self) { park in
            Button {
                if category == "Food" || category == "Merchandise" {
                    drillPark = park
                } else {
                    // For other categories, just set the park and close
                    selectedPark = park
                    selectedLocation = park
                    dismiss()
                }
            } label: {
                HStack {
                    Text(park)
                        .foregroundStyle(.primary)
                    Spacer()
                    if category == "Food" || category == "Merchandise" {
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Select Park")
        .searchable(text: $searchText, prompt: "Search")
    }

    private func locationList(for park: String) -> some View {
        let locs = locations(for: park)
            .filter { searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText) }

        return List(locs, id: \.self) { loc in
            let eligible = isEligible(location: loc, park: park)
            Button {
                selectedPark = park
                selectedLocation = loc
                isAPEligible = eligible
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc).foregroundStyle(.primary)
                        if category == "Food", let cat = diningCategory(for: loc) {
                            Text(cat)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if eligible {
                        Label("AP eligible", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("Not eligible")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(park)
        .searchable(text: $searchText, prompt: "Search \(park)")
    }

    // Universal: all locations inside USF, IOA, Epic Universe, and Volcano Bay are AP eligible.
    // CityWalk locations are also eligible (rate varies by pass tier, handled in PassSavingsView).
    // Disney food: only table-service and character dining qualify.
    // Disney merchandise: all curated store locations qualify.
    private func isEligible(location: String, park: String) -> Bool {
        if location == "Outdoor Cart / Quick Grab" { return false }

        if resort == ParkGroup.universal.rawValue {
            return true  // all Universal owned/operated locations are AP eligible
        }

        // Disney
        if category == "Merchandise" { return true }
        if category == "Food" {
            if let seed = allSeedRestaurants.first(where: { $0.name == location && $0.park == park }) {
                return seed.category == "Table Service" || seed.category == "Character Dining"
            }
            return false
        }
        return false
    }

    private func diningCategory(for name: String) -> String? {
        allSeedRestaurants.first(where: { $0.name == name })?.category
    }
}

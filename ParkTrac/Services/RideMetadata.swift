import SwiftUI

// MARK: - Enums

enum ThrillLevel: String, CaseIterable {
    case family    = "Family"
    case moderate  = "Moderate"
    case thrilling = "Thrilling"
    case extreme   = "Extreme"

    var color: Color {
        switch self {
        case .family:    return .green
        case .moderate:  return Color(red: 1, green: 0.75, blue: 0)
        case .thrilling: return .orange
        case .extreme:   return .red
        }
    }

    var systemImage: String {
        switch self {
        case .family:    return "face.smiling"
        case .moderate:  return "arrow.up.right"
        case .thrilling: return "bolt.fill"
        case .extreme:   return "flame.fill"
        }
    }
}

enum RideType: String {
    case coaster       = "Coaster"
    case darkRide      = "Dark Ride"
    case simulator     = "Simulator"
    case water         = "Water Ride"
    case aerial        = "Aerial"
    case transport     = "Transport"
    case family        = "Family Ride"
    case showOrLive    = "Show"
    case spinner       = "Spinner"

    var systemImage: String {
        switch self {
        case .coaster:    return "bolt.fill"
        case .darkRide:   return "moon.fill"
        case .simulator:  return "gamecontroller.fill"
        case .water:      return "drop.fill"
        case .aerial:     return "wind"
        case .transport:  return "tram.fill"
        case .family:     return "figure.2.and.child.holdinghands"
        case .showOrLive: return "theatermasks.fill"
        case .spinner:    return "arrow.2.circlepath"
        }
    }
}

struct RideInfo {
    let heightInches: Int?     // nil = no requirement
    let thrill: ThrillLevel
    let type: RideType
    let lightningLane: Bool    // true = Lightning Lane / Express Pass
    let isIndoor: Bool         // set true only where confidently known below

    init(heightInches: Int?, thrill: ThrillLevel, type: RideType, lightningLane: Bool, isIndoor: Bool = false) {
        self.heightInches = heightInches
        self.thrill = thrill
        self.type = type
        self.lightningLane = lightningLane
        self.isIndoor = isIndoor
    }
}

// MARK: - Ride Metadata Dictionary
// Keyed by exact ride name as returned by the themeparks.wiki API.
// isIndoor is best-effort — only set true where the ride is a fully enclosed
// building/show experience; anything open-air, canopy-covered, or mixed
// indoor/outdoor is left at the default false rather than guessed.

let rideMetadata: [String: RideInfo] = [

    // MARK: Magic Kingdom

    "Seven Dwarfs Mine Train": RideInfo(heightInches: 38, thrill: .moderate,  type: .coaster,   lightningLane: true),
    "TRON Lightcycle / Run":   RideInfo(heightInches: 40, thrill: .thrilling,  type: .coaster,   lightningLane: true),
    "Space Mountain":          RideInfo(heightInches: 44, thrill: .moderate,   type: .coaster,   lightningLane: true, isIndoor: true),
    "Big Thunder Mountain Railroad": RideInfo(heightInches: 40, thrill: .moderate, type: .coaster, lightningLane: true),
    "Tiana's Bayou Adventure": RideInfo(heightInches: 40, thrill: .moderate,   type: .water,     lightningLane: true),
    "Splash Mountain":         RideInfo(heightInches: 40, thrill: .moderate,   type: .water,     lightningLane: false),
    "Haunted Mansion":         RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: true, isIndoor: true),
    "Pirates of the Caribbean": RideInfo(heightInches: nil, thrill: .family,   type: .darkRide,  lightningLane: false, isIndoor: true),
    "Peter Pan's Flight":      RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: true, isIndoor: true),
    "The Many Adventures of Winnie the Pooh": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: true, isIndoor: true),
    "Buzz Lightyear's Space Ranger Spin": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: true, isIndoor: true),
    "It's a Small World":      RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: false, isIndoor: true),
    "Tomorrowland Speedway":   RideInfo(heightInches: 54, thrill: .family,     type: .family,    lightningLane: false),
    "Dumbo the Flying Elephant": RideInfo(heightInches: nil, thrill: .family,  type: .family,    lightningLane: false),
    "Mad Tea Party":           RideInfo(heightInches: nil, thrill: .family,    type: .spinner,   lightningLane: false),
    "The Barnstormer":         RideInfo(heightInches: 35, thrill: .family,     type: .coaster,   lightningLane: false),
    "Astro Orbiter":           RideInfo(heightInches: nil, thrill: .family,    type: .aerial,    lightningLane: false),
    "Tomorrowland Transit Authority PeopleMover": RideInfo(heightInches: nil, thrill: .family, type: .transport, lightningLane: false, isIndoor: true),
    "Walt Disney World Railroad": RideInfo(heightInches: nil, thrill: .family, type: .transport, lightningLane: false),
    "Liberty Square Riverboat": RideInfo(heightInches: nil, thrill: .family,   type: .transport, lightningLane: false),
    "Under the Sea - Journey of the Little Mermaid": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: false, isIndoor: true),
    "Prince Charming Regal Carrousel": RideInfo(heightInches: nil, thrill: .family, type: .family, lightningLane: false),

    // MARK: EPCOT

    "Guardians of the Galaxy: Cosmic Rewind": RideInfo(heightInches: 40, thrill: .thrilling, type: .coaster, lightningLane: true, isIndoor: true),
    "Test Track":              RideInfo(heightInches: 40, thrill: .moderate,   type: .simulator, lightningLane: true),
    "Soarin' Around the World": RideInfo(heightInches: 40, thrill: .family,    type: .aerial,    lightningLane: true, isIndoor: true),
    "Remy's Ratatouille Adventure": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: true, isIndoor: true),
    "Frozen Ever After":       RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: true, isIndoor: true),
    "Spaceship Earth":         RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: false, isIndoor: true),
    "Mission: SPACE":          RideInfo(heightInches: 40, thrill: .moderate,   type: .simulator, lightningLane: true, isIndoor: true),
    "Journey Into Imagination with Figment": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: false, isIndoor: true),
    "Living with the Land":    RideInfo(heightInches: nil, thrill: .family,    type: .transport, lightningLane: true, isIndoor: true),
    "The Seas with Nemo & Friends": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: false, isIndoor: true),

    // MARK: Hollywood Studios

    "Slinky Dog Dash":         RideInfo(heightInches: 38, thrill: .moderate,   type: .coaster,   lightningLane: true),
    "The Twilight Zone Tower of Terror": RideInfo(heightInches: 40, thrill: .thrilling, type: .darkRide, lightningLane: true, isIndoor: true),
    "Rock 'n' Roller Coaster Starring Aerosmith": RideInfo(heightInches: 48, thrill: .extreme, type: .coaster, lightningLane: true, isIndoor: true),
    "Star Wars: Rise of the Resistance": RideInfo(heightInches: nil, thrill: .thrilling, type: .darkRide, lightningLane: true, isIndoor: true),
    "Millennium Falcon: Smugglers Run": RideInfo(heightInches: 38, thrill: .moderate, type: .simulator, lightningLane: true, isIndoor: true),
    "Mickey & Minnie's Runaway Railway": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: true, isIndoor: true),
    "Toy Story Mania!":        RideInfo(heightInches: nil, thrill: .family,    type: .simulator, lightningLane: true, isIndoor: true),
    "Alien Swirling Saucers":  RideInfo(heightInches: 32, thrill: .family,     type: .spinner,   lightningLane: false),
    "MUPPET*VISION 3D":        RideInfo(heightInches: nil, thrill: .family,    type: .showOrLive, lightningLane: false, isIndoor: true),

    // MARK: Animal Kingdom

    "Expedition Everest - Legend of the Forbidden Mountain": RideInfo(heightInches: 44, thrill: .thrilling, type: .coaster, lightningLane: true),
    "Kilimanjaro Safaris":     RideInfo(heightInches: nil, thrill: .family,    type: .family,    lightningLane: true),
    "Avatar Flight of Passage": RideInfo(heightInches: 44, thrill: .thrilling, type: .simulator, lightningLane: true, isIndoor: true),
    "Na'vi River Journey":     RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: true, isIndoor: true),
    "DINOSAUR":                RideInfo(heightInches: 40, thrill: .thrilling,  type: .darkRide,  lightningLane: true, isIndoor: true),
    "Kali River Rapids":       RideInfo(heightInches: 38, thrill: .moderate,   type: .water,     lightningLane: true),
    "TriceraTop Spin":         RideInfo(heightInches: nil, thrill: .family,    type: .family,    lightningLane: false),

    // MARK: Universal Studios Florida

    "Hollywood Rip Ride Rockit": RideInfo(heightInches: 51, thrill: .extreme,  type: .coaster,   lightningLane: false),
    "Transformers: The Ride-3D": RideInfo(heightInches: nil, thrill: .thrilling, type: .simulator, lightningLane: false, isIndoor: true),
    "Despicable Me Minion Mayhem": RideInfo(heightInches: nil, thrill: .family, type: .simulator, lightningLane: false, isIndoor: true),
    "Revenge of the Mummy":    RideInfo(heightInches: 48, thrill: .thrilling,   type: .coaster,   lightningLane: false, isIndoor: true),
    "Harry Potter and the Escape from Gringotts": RideInfo(heightInches: 42, thrill: .moderate, type: .darkRide, lightningLane: false, isIndoor: true),
    "Race Through New York Starring Jimmy Fallon": RideInfo(heightInches: nil, thrill: .family, type: .simulator, lightningLane: false, isIndoor: true),
    "Fast & Furious - Supercharged": RideInfo(heightInches: nil, thrill: .moderate, type: .simulator, lightningLane: false, isIndoor: true),
    "E.T. Adventure":          RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: false, isIndoor: true),
    "MEN IN BLACK Alien Attack": RideInfo(heightInches: nil, thrill: .family,   type: .darkRide,  lightningLane: false, isIndoor: true),

    // MARK: Islands of Adventure

    "Hagrid's Magical Creatures Motorbike Adventure": RideInfo(heightInches: 36, thrill: .moderate, type: .coaster, lightningLane: false),
    "VelociCoaster":           RideInfo(heightInches: 51, thrill: .extreme,    type: .coaster,   lightningLane: false),
    "Harry Potter and the Forbidden Journey": RideInfo(heightInches: 48, thrill: .thrilling, type: .simulator, lightningLane: false, isIndoor: true),
    "Flight of the Hippogriff": RideInfo(heightInches: 36, thrill: .moderate,  type: .coaster,   lightningLane: false),
    "The Amazing Adventures of Spider-Man": RideInfo(heightInches: 40, thrill: .moderate, type: .simulator, lightningLane: false, isIndoor: true),
    "The Incredible Hulk Coaster": RideInfo(heightInches: 54, thrill: .extreme, type: .coaster,  lightningLane: false),
    "Doctor Doom's Fearfall":  RideInfo(heightInches: 52, thrill: .extreme,    type: .family,    lightningLane: false),
    "Jurassic World Adventure": RideInfo(heightInches: 42, thrill: .moderate,  type: .water,     lightningLane: false),
    "Jurassic Park River Adventure": RideInfo(heightInches: 42, thrill: .moderate, type: .water, lightningLane: false),
    "Popeye & Bluto's Bilge-Rat Barges": RideInfo(heightInches: 42, thrill: .moderate, type: .water, lightningLane: false),
    "Dudley Do-Right's Ripsaw Falls": RideInfo(heightInches: 44, thrill: .moderate, type: .water, lightningLane: false),
    "Pteranodon Flyers":       RideInfo(heightInches: 36, thrill: .family,     type: .aerial,    lightningLane: false),

    // MARK: Epic Universe

    "Harry Potter and the Battle at the Ministry": RideInfo(heightInches: 40, thrill: .thrilling, type: .darkRide, lightningLane: false, isIndoor: true),
    "Monsters Unchained: The Frankenstein Experiment": RideInfo(heightInches: 48, thrill: .extreme, type: .coaster, lightningLane: false, isIndoor: true),
    "STARFALL Racers":         RideInfo(heightInches: 48, thrill: .extreme,    type: .coaster,   lightningLane: false),
    "Space Race":              RideInfo(heightInches: 40, thrill: .thrilling,  type: .coaster,   lightningLane: false),
    "Constellation Carousel":  RideInfo(heightInches: nil, thrill: .family,   type: .family,    lightningLane: false),
    "Curse of the Werewolf":   RideInfo(heightInches: 48, thrill: .extreme,    type: .coaster,   lightningLane: false, isIndoor: true),
]

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

extension RideInfo {
    /// Dark rides, simulators and shows are indoors
    var isIndoorByType: Bool { type == .darkRide || type == .simulator || type == .showOrLive }
}

struct RideInfo {
    let heightInches: Int?     // nil = no requirement (Orlando rides are published in inches)
    let heightCm: Int?         // Japan rides are published in centimetres
    let maxHeightCm: Int?      // a few Japan coasters also have a maximum
    let thrill: ThrillLevel
    let type: RideType
    let lightningLane: Bool    // true = Lightning Lane / Express Pass / Priority Pass

    init(heightInches: Int?, thrill: ThrillLevel, type: RideType, lightningLane: Bool) {
        self.heightInches = heightInches
        self.heightCm = nil
        self.maxHeightCm = nil
        self.thrill = thrill
        self.type = type
        self.lightningLane = lightningLane
    }

    init(heightCm: Int?, maxCm: Int? = nil, thrill: ThrillLevel, type: RideType) {
        self.heightInches = nil
        self.heightCm = heightCm
        self.maxHeightCm = maxCm
        self.thrill = thrill
        self.type = type
        self.lightningLane = false   // Japan's return passes come from live data, not this table
    }

    /// Minimum height in centimetres, whichever unit it was published in.
    var minimumCm: Double? {
        if let heightCm { return Double(heightCm) }
        return heightInches.map { Double($0) * 2.54 }
    }

    var hasHeightRequirement: Bool { minimumCm != nil }

    /// Can a guest of this height ride? (Ignores the maximum — the checker is for kids.)
    func allows(heightCm guest: Double) -> Bool {
        guard let min = minimumCm else { return true }
        return guest + 0.01 >= min
    }
}

// MARK: - Height formatting

/// Shows each ride's height in the unit the user wants, converting from the unit it was published in.
/// Published values are shown as-is (102 cm stays 102 cm); conversions are rounded.
enum HeightFormat {
    static func inches(_ info: RideInfo) -> Int? {
        if let h = info.heightInches { return h }
        return info.heightCm.map { Int((Double($0) / 2.54).rounded()) }
    }

    static func centimetres(_ info: RideInfo) -> Int? {
        if let cm = info.heightCm { return cm }
        return info.heightInches.map { Int((Double($0) * 2.54).rounded()) }
    }

    /// "102 cm" / "40\"", nil when there's no requirement.
    static func short(_ info: RideInfo, metric: Bool) -> String? {
        metric ? centimetres(info).map { "\($0) cm" } : inches(info).map { "\($0)\"" }
    }

    /// For VoiceOver: "102 centimeters" / "40 inches".
    static func spoken(_ info: RideInfo, metric: Bool) -> String? {
        metric ? centimetres(info).map { "\($0) centimeters" } : inches(info).map { "\($0) inches" }
    }

    /// A guest's own height: "122 cm" / "4' 0\"".
    static func guest(cm: Double, metric: Bool) -> String {
        if metric { return "\(Int(cm.rounded())) cm" }
        let total = Int((cm / 2.54).rounded())
        return "\(total / 12)' \(total % 12)\""
    }
}

// MARK: - Lookup

enum RideMetadata {
    /// The metadata table for a resort. Orlando shares one table (both resorts' names are unique).
    static func catalog(for resort: ParkGroup) -> [String: RideInfo] {
        switch resort {
        case .disney, .universal: return rideMetadata
        case .tokyoDisney:        return tokyoDisneyRideMetadata
        case .universalJapan:     return universalJapanRideMetadata
        }
    }

    /// Rides you stay dry on even though their type isn't a dark ride / simulator / show
    /// (indoor coasters, indoor boats and trams). Compared normalized, across all resorts.
    static let indoorOverrides: Set<String> = Set([
        "Space Mountain",
        "Guardians of the Galaxy: Cosmic Rewind",
        "Rock 'n' Roller Coaster Starring Aerosmith",
        "Rock 'n' Roller Coaster",
        "Soarin' Around the World",
        "Soaring: Fantastic Flight",
        "Revenge of the Mummy",
        "Monsters Unchained: The Frankenstein Experiment",
        "Living with the Land",
    ].map { RideMetadata.normalize($0) })

    /// Rides with a standing single rider queue — Universal only; Disney doesn't run them.
    /// Compared normalized, across all four resorts. Sourced Sept 2026; single rider is turned
    /// on and off by operations, so this says a ride *has* one, not that it's open right now
    /// (the live API has no per-ride single rider signal to check).
    static let singleRiderRides: Set<String> = Set([
        // Universal Orlando — Islands of Adventure
        "The Amazing Adventures of Spider-Man", "Doctor Doom's Fearfall",
        "Dudley Do-Right's Ripsaw Falls", "Hagrid's Magical Creatures Motorbike Adventure",
        "Harry Potter and the Forbidden Journey", "The Incredible Hulk Coaster",
        "Jurassic Park River Adventure", "Jurassic World VelociCoaster",
        // Universal Orlando — Universal Studios Florida
        "Harry Potter and the Escape from Gringotts", "Men in Black Alien Attack",
        // Epic Universe
        "Stardust Racers", "Mario Kart: Bowser's Challenge", "Mine-Cart Madness",
        "Hiccup's Wing Gliders", "Curse of the Werewolf", "Monsters Unchained: The Frankenstein Experiment",
        "Harry Potter and the Battle at the Ministry", "Yoshi's Adventure",
        // Universal Studios Japan
        "Hollywood Dream – The Ride", "Space Fantasy – The Ride",
    ].map { RideMetadata.normalize($0) })

    static func hasSingleRider(name: String, resort: ParkGroup) -> Bool {
        guard resort != .disney, resort != .tokyoDisney else { return false }   // Disney parks don't run single rider
        let key = normalize(name)
        return singleRiderRides.contains(key) || singleRiderRides.contains(where: { $0.count >= 10 && key.contains($0) })
    }

    /// Mostly indoors, so it keeps running (and you stay dry) in the rain.
    static func isIndoor(name: String, resort: ParkGroup) -> Bool {
        let key = normalize(name)
        if indoorOverrides.contains(key) || indoorOverrides.contains(where: { $0.count >= 10 && key.contains($0) }) {
            return true
        }
        return info(for: name, resort: resort)?.isIndoorByType ?? false
    }

    /// Japan resorts publish heights in cm; Orlando in inches.
    static func prefersMetric(_ resort: ParkGroup) -> Bool { !resort.isOrlando }

    /// Lowercased letters and digits only, so "Indiana Jones® Adventure: Temple…" and
    /// "Indiana Jones Adventure - Temple…" compare equal.
    static func normalize(_ name: String) -> String {
        String(name.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
            .map(Character.init))
    }

    /// Finds a ride's metadata by its themeparks.wiki name: exact, then punctuation-insensitive,
    /// then (for longer names) an API name that contains a known name, e.g. "Hollywood Dream – The Ride ~Backdrop~".
    static func info(for name: String, resort: ParkGroup) -> RideInfo? {
        let table = catalog(for: resort)
        if let exact = table[name] { return exact }
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        var containsMatch: (length: Int, info: RideInfo)?
        for (candidate, info) in table {
            let c = normalize(candidate)
            if c == key { return info }
            // Longest contained name wins; short names are too ambiguous to match inside others
            if c.count >= 10, key.contains(c), c.count > (containsMatch?.length ?? 0) {
                containsMatch = (c.count, info)
            }
        }
        return containsMatch?.info
    }
}

// MARK: - Alternate ride suggestion (pure)
// A shorter standby wait is the only accommodation left for a lot of guests since Disney
// tightened DAS eligibility — this surfaces the two real ways to cut a long standby without
// a return-time pass: a single rider queue on the same ride, or a similar ride nearby that's
// currently shorter. Never a manufactured claim about accessibility — just wait-time facts.

enum AlternateRideSuggestion {
    enum Kind: Equatable {
        case singleRider
        case similarRide(name: String, waitMinutes: Int)
    }

    /// Only worth suggesting an alternative once the wait is genuinely long.
    static let busyThresholdMinutes = 40

    /// `candidates` should be every other operating ride at the same park (not just Must-Dos),
    /// so a short-wait alternative can be found even if it isn't starred.
    static func suggest(rideName: String, waitMinutes: Int?, isOperating: Bool,
                        candidates: [(name: String, waitMinutes: Int?, isOperating: Bool)],
                        resort: ParkGroup) -> Kind? {
        guard isOperating, let wait = waitMinutes, wait >= busyThresholdMinutes else { return nil }
        if hasSingleRider(name: rideName, resort: resort) { return .singleRider }
        guard let info = info(for: rideName, resort: resort) else { return nil }
        let best = candidates
            .compactMap { c -> (name: String, wait: Int)? in
                guard c.isOperating, let cw = c.waitMinutes, cw < wait - 15, cw <= wait / 2,
                      let cInfo = info(for: c.name, resort: resort), cInfo.type == info.type else { return nil }
                return (c.name, cw)
            }
            .min { $0.wait < $1.wait }
        guard let best else { return nil }
        return .similarRide(name: best.name, waitMinutes: best.wait)
    }
}

// MARK: - Rest stop suggestion (pure)
// Without a return-time pass, pacing a long day means finding somewhere to sit and cool off
// without adding a standby wait. Indoor rides and shows (already tracked via `isIndoor`) are
// the practical answer — no new geo data to maintain, no accessibility claim, just "here's
// somewhere air-conditioned and seated you can go right now."

enum RestStopSuggestion {
    enum Kind: Equatable {
        case show(name: String, startsInMinutes: Int)
        case ride(name: String, waitMinutes: Int)
    }

    /// A show starting soon beats an indoor ride (guaranteed seated, no line to stand in);
    /// among indoor rides, the shortest wait wins. nil if nothing indoor is available.
    static func pick(shows: [(name: String, isOperating: Bool, startsInMinutes: Int?)],
                     rides: [(name: String, isOperating: Bool, waitMinutes: Int?)],
                     resort: ParkGroup, showLeadMinutes: Int = 30) -> Kind? {
        let soonShow = shows
            .compactMap { s -> (name: String, minutes: Int)? in
                guard s.isOperating, let minutes = s.startsInMinutes, minutes <= showLeadMinutes else { return nil }
                return (s.name, minutes)
            }
            .min { $0.minutes < $1.minutes }
        if let soonShow { return .show(name: soonShow.name, startsInMinutes: soonShow.minutes) }

        let indoorRide = rides
            .compactMap { r -> (name: String, wait: Int)? in
                guard r.isOperating, let wait = r.waitMinutes, isIndoor(name: r.name, resort: resort) else { return nil }
                return (r.name, wait)
            }
            .min { $0.wait < $1.wait }
        return indoorRide.map { .ride(name: $0.name, waitMinutes: $0.wait) }
    }

    static func text(_ kind: Kind) -> String {
        switch kind {
        case .show(let name, let minutes):
            return minutes <= 1 ? "\(name) is starting now — seated, indoors." : "\(name) starts in \(minutes) min — seated, indoors."
        case .ride(let name, let wait):
            return wait == 0 ? "\(name) — walk on, indoors." : "\(name) — \(wait) min wait, indoors."
        }
    }
}

// MARK: - Ride Metadata Dictionary
// Keyed by exact ride name as returned by the themeparks.wiki API.

let rideMetadata: [String: RideInfo] = [

    // MARK: Magic Kingdom

    "Seven Dwarfs Mine Train": RideInfo(heightInches: 38, thrill: .moderate,  type: .coaster,   lightningLane: true),
    "TRON Lightcycle / Run":   RideInfo(heightInches: 40, thrill: .thrilling,  type: .coaster,   lightningLane: true),
    "Space Mountain":          RideInfo(heightInches: 44, thrill: .moderate,   type: .coaster,   lightningLane: true),
    "Big Thunder Mountain Railroad": RideInfo(heightInches: 40, thrill: .moderate, type: .coaster, lightningLane: true),
    "Tiana's Bayou Adventure": RideInfo(heightInches: 40, thrill: .moderate,   type: .water,     lightningLane: true),
    "Splash Mountain":         RideInfo(heightInches: 40, thrill: .moderate,   type: .water,     lightningLane: false),
    "Haunted Mansion":         RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: true),
    "Pirates of the Caribbean": RideInfo(heightInches: nil, thrill: .family,   type: .darkRide,  lightningLane: false),
    "Peter Pan's Flight":      RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: true),
    "The Many Adventures of Winnie the Pooh": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: true),
    "Buzz Lightyear's Space Ranger Spin": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: true),
    "It's a Small World":      RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: false),
    "Tomorrowland Speedway":   RideInfo(heightInches: 54, thrill: .family,     type: .family,    lightningLane: false),
    "Dumbo the Flying Elephant": RideInfo(heightInches: nil, thrill: .family,  type: .family,    lightningLane: false),
    "Mad Tea Party":           RideInfo(heightInches: nil, thrill: .family,    type: .spinner,   lightningLane: false),
    "The Barnstormer":         RideInfo(heightInches: 35, thrill: .family,     type: .coaster,   lightningLane: false),
    "Astro Orbiter":           RideInfo(heightInches: nil, thrill: .family,    type: .aerial,    lightningLane: false),
    "Tomorrowland Transit Authority PeopleMover": RideInfo(heightInches: nil, thrill: .family, type: .transport, lightningLane: false),
    "Walt Disney World Railroad": RideInfo(heightInches: nil, thrill: .family, type: .transport, lightningLane: false),
    "Liberty Square Riverboat": RideInfo(heightInches: nil, thrill: .family,   type: .transport, lightningLane: false),
    "Under the Sea - Journey of the Little Mermaid": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: false),
    "Prince Charming Regal Carrousel": RideInfo(heightInches: nil, thrill: .family, type: .family, lightningLane: false),

    // MARK: EPCOT

    "Guardians of the Galaxy: Cosmic Rewind": RideInfo(heightInches: 40, thrill: .thrilling, type: .coaster, lightningLane: true),
    "Test Track":              RideInfo(heightInches: 40, thrill: .moderate,   type: .simulator, lightningLane: true),
    "Soarin' Around the World": RideInfo(heightInches: 40, thrill: .family,    type: .aerial,    lightningLane: true),
    "Remy's Ratatouille Adventure": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: true),
    "Frozen Ever After":       RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: true),
    "Spaceship Earth":         RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: false),
    "Mission: SPACE":          RideInfo(heightInches: 40, thrill: .moderate,   type: .simulator, lightningLane: true),
    "Journey Into Imagination with Figment": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: false),
    "Living with the Land":    RideInfo(heightInches: nil, thrill: .family,    type: .transport, lightningLane: true),
    "The Seas with Nemo & Friends": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: false),

    // MARK: Hollywood Studios

    "Slinky Dog Dash":         RideInfo(heightInches: 38, thrill: .moderate,   type: .coaster,   lightningLane: true),
    "The Twilight Zone Tower of Terror": RideInfo(heightInches: 40, thrill: .thrilling, type: .darkRide, lightningLane: true),
    "Rock 'n' Roller Coaster Starring Aerosmith": RideInfo(heightInches: 48, thrill: .extreme, type: .coaster, lightningLane: true),
    "Star Wars: Rise of the Resistance": RideInfo(heightInches: nil, thrill: .thrilling, type: .darkRide, lightningLane: true),
    "Millennium Falcon: Smugglers Run": RideInfo(heightInches: 38, thrill: .moderate, type: .simulator, lightningLane: true),
    "Mickey & Minnie's Runaway Railway": RideInfo(heightInches: nil, thrill: .family, type: .darkRide, lightningLane: true),
    "Toy Story Mania!":        RideInfo(heightInches: nil, thrill: .family,    type: .simulator, lightningLane: true),
    "Alien Swirling Saucers":  RideInfo(heightInches: 32, thrill: .family,     type: .spinner,   lightningLane: false),
    "MUPPET*VISION 3D":        RideInfo(heightInches: nil, thrill: .family,    type: .showOrLive, lightningLane: false),

    // MARK: Animal Kingdom

    "Expedition Everest - Legend of the Forbidden Mountain": RideInfo(heightInches: 44, thrill: .thrilling, type: .coaster, lightningLane: true),
    "Kilimanjaro Safaris":     RideInfo(heightInches: nil, thrill: .family,    type: .family,    lightningLane: true),
    "Avatar Flight of Passage": RideInfo(heightInches: 44, thrill: .thrilling, type: .simulator, lightningLane: true),
    "Na'vi River Journey":     RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: true),
    "DINOSAUR":                RideInfo(heightInches: 40, thrill: .thrilling,  type: .darkRide,  lightningLane: true),
    "Kali River Rapids":       RideInfo(heightInches: 38, thrill: .moderate,   type: .water,     lightningLane: true),
    "TriceraTop Spin":         RideInfo(heightInches: nil, thrill: .family,    type: .family,    lightningLane: false),

    // MARK: Universal Studios Florida

    "Hollywood Rip Ride Rockit": RideInfo(heightInches: 51, thrill: .extreme,  type: .coaster,   lightningLane: false),
    "Transformers: The Ride-3D": RideInfo(heightInches: nil, thrill: .thrilling, type: .simulator, lightningLane: false),
    "Despicable Me Minion Mayhem": RideInfo(heightInches: nil, thrill: .family, type: .simulator, lightningLane: false),
    "Revenge of the Mummy":    RideInfo(heightInches: 48, thrill: .thrilling,   type: .coaster,   lightningLane: false),
    "Harry Potter and the Escape from Gringotts": RideInfo(heightInches: 42, thrill: .moderate, type: .darkRide, lightningLane: false),
    "Race Through New York Starring Jimmy Fallon": RideInfo(heightInches: nil, thrill: .family, type: .simulator, lightningLane: false),
    "Fast & Furious - Supercharged": RideInfo(heightInches: nil, thrill: .moderate, type: .simulator, lightningLane: false),
    "E.T. Adventure":          RideInfo(heightInches: nil, thrill: .family,    type: .darkRide,  lightningLane: false),
    "MEN IN BLACK Alien Attack": RideInfo(heightInches: nil, thrill: .family,   type: .darkRide,  lightningLane: false),

    // MARK: Islands of Adventure

    "Hagrid's Magical Creatures Motorbike Adventure": RideInfo(heightInches: 36, thrill: .moderate, type: .coaster, lightningLane: false),
    "VelociCoaster":           RideInfo(heightInches: 51, thrill: .extreme,    type: .coaster,   lightningLane: false),
    "Harry Potter and the Forbidden Journey": RideInfo(heightInches: 48, thrill: .thrilling, type: .simulator, lightningLane: false),
    "Flight of the Hippogriff": RideInfo(heightInches: 36, thrill: .moderate,  type: .coaster,   lightningLane: false),
    "The Amazing Adventures of Spider-Man": RideInfo(heightInches: 40, thrill: .moderate, type: .simulator, lightningLane: false),
    "The Incredible Hulk Coaster": RideInfo(heightInches: 54, thrill: .extreme, type: .coaster,  lightningLane: false),
    "Doctor Doom's Fearfall":  RideInfo(heightInches: 52, thrill: .extreme,    type: .family,    lightningLane: false),
    "Jurassic World Adventure": RideInfo(heightInches: 42, thrill: .moderate,  type: .water,     lightningLane: false),
    "Jurassic Park River Adventure": RideInfo(heightInches: 42, thrill: .moderate, type: .water, lightningLane: false),
    "Popeye & Bluto's Bilge-Rat Barges": RideInfo(heightInches: 42, thrill: .moderate, type: .water, lightningLane: false),
    "Dudley Do-Right's Ripsaw Falls": RideInfo(heightInches: 44, thrill: .moderate, type: .water, lightningLane: false),
    "Pteranodon Flyers":       RideInfo(heightInches: 36, thrill: .family,     type: .aerial,    lightningLane: false),

    // MARK: Epic Universe

    "Harry Potter and the Battle at the Ministry": RideInfo(heightInches: 40, thrill: .thrilling, type: .darkRide, lightningLane: false),
    "Monsters Unchained: The Frankenstein Experiment": RideInfo(heightInches: 48, thrill: .extreme, type: .coaster, lightningLane: false),
    "STARFALL Racers":         RideInfo(heightInches: 48, thrill: .extreme,    type: .coaster,   lightningLane: false),
    "Space Race":              RideInfo(heightInches: 40, thrill: .thrilling,  type: .coaster,   lightningLane: false),
    "Constellation Carousel":  RideInfo(heightInches: nil, thrill: .family,   type: .family,    lightningLane: false),
    "Curse of the Werewolf":   RideInfo(heightInches: 48, thrill: .extreme,    type: .coaster,   lightningLane: false),
]

// MARK: - Tokyo Disney Resort
// Heights in cm from the resort's published requirements (compiled Sept 2026 — confirm in the park).
// Keyed by English name; matching is punctuation-insensitive (RideMetadata.info).

let tokyoDisneyRideMetadata: [String: RideInfo] = [

    // Tokyo Disneyland
    "Big Thunder Mountain":    RideInfo(heightCm: 102, thrill: .moderate,  type: .coaster),
    "Splash Mountain":         RideInfo(heightCm: 90,  thrill: .moderate,  type: .water),
    "Space Mountain":          RideInfo(heightCm: 102, thrill: .moderate,  type: .coaster),
    "Star Tours: The Adventures Continue": RideInfo(heightCm: 102, thrill: .moderate, type: .simulator),
    "Gadget's Go Coaster":     RideInfo(heightCm: 90,  thrill: .family,    type: .coaster),
    "Enchanted Tale of Beauty and the Beast": RideInfo(heightCm: nil, thrill: .family, type: .darkRide),
    "Haunted Mansion":         RideInfo(heightCm: nil, thrill: .family,    type: .darkRide),
    "Pirates of the Caribbean": RideInfo(heightCm: nil, thrill: .family,   type: .darkRide),
    "Pooh's Hunny Hunt":       RideInfo(heightCm: nil, thrill: .family,    type: .darkRide),
    "Monsters, Inc. Ride & Go Seek!": RideInfo(heightCm: nil, thrill: .family, type: .darkRide),
    "Buzz Lightyear's Astro Blasters": RideInfo(heightCm: nil, thrill: .family, type: .darkRide),
    "\"it's a small world\"":  RideInfo(heightCm: nil, thrill: .family,    type: .darkRide),

    // Tokyo DisneySea
    "Soaring: Fantastic Flight": RideInfo(heightCm: 102, thrill: .family,  type: .aerial),
    "Tower of Terror":         RideInfo(heightCm: 102, thrill: .thrilling, type: .darkRide),
    "Toy Story Mania!":        RideInfo(heightCm: nil, thrill: .family,    type: .simulator),
    "Nemo & Friends SeaRider": RideInfo(heightCm: 90,  thrill: .family,    type: .simulator),
    "Peter Pan's Never Land Adventure": RideInfo(heightCm: 102, thrill: .moderate, type: .darkRide),
    "Frozen Journey":          RideInfo(heightCm: nil, thrill: .family,    type: .darkRide),
    "Rapunzel's Lantern Festival": RideInfo(heightCm: nil, thrill: .family, type: .darkRide),
    "Indiana Jones Adventure: Temple of the Crystal Skull": RideInfo(heightCm: 117, thrill: .thrilling, type: .darkRide),
    "Journey to the Center of the Earth": RideInfo(heightCm: 117, thrill: .thrilling, type: .darkRide),
    "Raging Spirits":          RideInfo(heightCm: 117, maxCm: 195, thrill: .extreme, type: .coaster),
    "20,000 Leagues Under the Sea": RideInfo(heightCm: nil, thrill: .family, type: .darkRide),
]

// MARK: - Universal Studios Japan

let universalJapanRideMetadata: [String: RideInfo] = [
    "The Flying Dinosaur":     RideInfo(heightCm: 132, maxCm: 198, thrill: .extreme, type: .coaster),
    "Hollywood Dream - The Ride": RideInfo(heightCm: 132, thrill: .extreme, type: .coaster),
    "Harry Potter and the Forbidden Journey": RideInfo(heightCm: 122, thrill: .thrilling, type: .simulator),
    "Flight of the Hippogriff": RideInfo(heightCm: 92,  thrill: .moderate, type: .coaster),
    "Mario Kart: Koopa's Challenge": RideInfo(heightCm: 102, thrill: .moderate, type: .darkRide),
    "Yoshi's Adventure":       RideInfo(heightCm: 86,  thrill: .family,    type: .family),
    "Mine-Cart Madness":       RideInfo(heightCm: 107, thrill: .moderate,  type: .coaster),
    "Jurassic Park - The Ride": RideInfo(heightCm: 107, thrill: .moderate, type: .water),
    "Despicable Me Minion Mayhem": RideInfo(heightCm: 102, thrill: .moderate, type: .simulator),
    "Jaws":                    RideInfo(heightCm: nil, thrill: .family,    type: .water),
]

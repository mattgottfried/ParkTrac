import Foundation
import CoreLocation
import MapKit
import UIKit
import UserNotifications

// MARK: - Parking spot

/// Where you parked today at a resort. The spot (location + note) syncs between your
/// devices through iCloud key-value storage; the photo stays on the phone that took it.
struct ParkingSpot: Codable, Equatable {
    var latitude: Double?
    var longitude: Double?
    /// "Zurg 112", "Level 4, Hollywood row"…
    var note: String
    var resortRaw: String
    var savedAt: Date
    // Picked from the lot menus (like the Disney app). Optional: older spots and Japan use the note.
    var lot: String? = nil
    var section: String? = nil
    var level: Int? = nil
    var row: String? = nil

    var details: ParkingDetails {
        get { ParkingDetails(lot: lot, section: section, level: level, row: row) }
        set { lot = newValue.lot; section = newValue.section; level = newValue.level; row = newValue.row }
    }

    var resort: ParkGroup { ParkGroup(rawValue: resortRaw) ?? .disney }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let c = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(c) ? c : nil
    }

    /// A spot is for one park day; after this it's hidden (and replaced by the next save).
    static let lifetime: TimeInterval = 20 * 3600

    func isCurrent(now: Date = .now) -> Bool {
        now.timeIntervalSince(savedAt) < Self.lifetime && savedAt <= now.addingTimeInterval(300)
    }

    var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "Zurg · Row 112", else the note, else "Parking spot" (map pin, My Day row)
    var title: String {
        let location = details.locationText
        if !location.isEmpty { return location }
        return trimmedNote.isEmpty ? "Parking spot" : trimmedNote
    }

    /// Everything: "Magic Kingdom · Zurg · Row 112 · near the tram stop" (reminder, directions)
    var summary: String {
        [details.lot ?? "", details.locationText, trimmedNote].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Lot → section → level → row, as picked from the menus.
struct ParkingDetails: Equatable {
    var lot: String?
    var section: String?
    var level: Int?
    var row: String?

    static let empty = ParkingDetails()

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Blank strings become nil so "nothing picked" compares equal to `.empty`
    var normalized: ParkingDetails {
        ParkingDetails(lot: Self.clean(lot), section: Self.clean(section), level: level, row: Self.clean(row))
    }

    var isEmpty: Bool { normalized == .empty }

    /// "Zurg · Row 112", "Lime Garage · Level 3", "King Kong · 410"
    var locationText: String {
        let d = normalized
        var parts: [String] = []
        if let section = d.section { parts.append(section) }
        if let level = d.level { parts.append("Level \(level)") }
        if let row = d.row {
            let label = d.lot.flatMap(ParkingLots.lot(named:))?.rowLabel ?? "Row"
            parts.append(label.isEmpty ? row : "\(label) \(row)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Lots (the Disney / Universal app menus)

struct ParkingSection: Equatable {
    var name: String
    /// Row signs in order, as the parks' apps list them ("100"…"109", or "Peak"); empty = no rows
    var rows: [String]
}

struct ParkingLot: Identifiable, Equatable {
    struct Group: Equatable {
        /// "Heroes", "Villains", "North Garage"… (nil = one plain list)
        var name: String?
        var sections: [ParkingSection]
    }

    var name: String
    var groups: [Group]
    /// Garages with numbered levels (Disney Springs)
    var levels: ClosedRange<Int>? = nil
    /// "Row" on Disney lots; empty where the sign shows a bare number (Universal "King Kong 410")
    var rowLabel: String = "Row"
    var rowPrompt: String = "e.g. 112"
    /// Rows for lots without sections (Blizzard Beach, Typhoon Lagoon)
    var rows: [String] = []
    /// Multi-level garage — GPS can't tell the level, so no row guessing
    var isGarage: Bool = false

    var id: String { name }
    var allSections: [String] { groups.flatMap(\.sections).map(\.name) }

    /// The row wheel's values for a section (or the lot itself when it has no sections)
    func rows(for section: String?) -> [String] {
        guard let section else { return groups.isEmpty ? rows : [] }
        return groups.flatMap(\.sections).first { $0.name == section }?.rows ?? []
    }
}

/// Section names and row numbers from the Disney and Universal apps (Sept 2026 — lots get
/// renamed now and then; "Other" + the note covers anything missing).
enum ParkingLots {
    /// "100"…"109" plus any extra signs
    static func r(_ ranges: ClosedRange<Int>..., extra: [String] = []) -> [String] {
        ranges.flatMap { $0.map(String.init) } + extra
    }

    private static func s(_ name: String, _ rows: [String]) -> ParkingSection {
        ParkingSection(name: name, rows: rows)
    }

    static let disney: [ParkingLot] = [
        ParkingLot(name: "Magic Kingdom", groups: [
            .init(name: "Heroes", sections: [
                s("Woody", r(100...109)), s("Simba", r(110...126)), s("Mulan", r(127...146)),
                s("Aladdin", r(200...208)), s("Peter Pan", r(209...225)), s("Rapunzel", r(226...237)),
            ]),
            .init(name: "Villains", sections: [
                s("Jafar", r(304...311)), s("Hook", r(312...328)), s("Ursula", r(329...340)),
                s("Zurg", r(400...408)), s("Scar", r(410...426)), s("Cruella", r(427...436)),
            ]),
            .init(name: "Accessible", sections: [s("Medical", r(300...303))]),
        ]),
        ParkingLot(name: "EPCOT", groups: [
            .init(name: nil, sections: [
                s("HeiHei", r(101...110)), s("Crush", r(201...216)), s("Moana", r(301...310)),
                s("Dory", r(401...417)), s("WALL-E", r(501...513)), s("Rocket", r(601...616)),
                s("Eve", r(701...713)), s("Gamora", r(801...820)),
            ]),
        ]),
        ParkingLot(name: "Hollywood Studios", groups: [
            .init(name: nil, sections: [
                s("Minnie", r(101...117)), s("Jessie", r(201...215)), s("Mickey", r(300...315)),
                s("Buzz", r(401...414)), s("Olaf", r(501...509)), s("BB-8", r(610...628)),
            ]),
        ]),
        ParkingLot(name: "Animal Kingdom", groups: [
            .init(name: nil, sections: [
                s("Peacock", r(104...118)), s("Butterfly", r(119...131)), s("Unicorn", r(209...217)),
                s("Dinosaur", r(218...226)), s("Giraffe", r(227...235)), s("Yeti", r(236...245)),
            ]),
            .init(name: "Accessible", sections: [s("Medical", r(100...103))]),
        ]),
        ParkingLot(name: "Disney Springs", groups: [
            .init(name: nil, sections: [s("Orange Garage", []), s("Lime Garage", []), s("Grapefruit Garage", [])]),
        ], levels: 1...7, rowLabel: "Row", rowPrompt: "Optional", isGarage: true),
        ParkingLot(name: "Blizzard Beach", groups: [], rows: r(1...18)),
        ParkingLot(name: "Typhoon Lagoon", groups: [], rows: r(1...18, extra: ["Peak"])),
    ]

    static let universal: [ParkingLot] = [
        ParkingLot(name: "CityWalk Garages", groups: [
            .init(name: nil, sections: [s("Valet", [])]),
            .init(name: "North Garage", sections: [
                s("Jurassic Park", r(100...106, 200...205, 300...306, 400...406, 500...506)),
                s("King Kong", r(107...112, 206...211, 307...312, 407...412, 507...512)),
                s("Jaws", r(113...118, 212...217, 313...318, 414...418, 514...518)),
            ]),
            .init(name: "South Garage", sections: [
                s("Spider-Man", r(150...156, 250...255, 350...356, 450...456, 550...556, 650...656)),
                s("Cat in the Hat", r(157...161, 256...260, 357...361, 457...461, 557...561, 657...661)),
                s("E.T.", r(162...167, 261...266, 362...367, 462...467, 562...567, 662...667)),
            ]),
        ], rowLabel: "", rowPrompt: "Number on the sign, e.g. 410", isGarage: true),
        ParkingLot(name: "Epic Universe", groups: [
            .init(name: nil, sections: [
                s("Valet", []), s("Explorer", r(101...107)), s("Monster", r(201...211)),
                s("Viking", r(301...311)), s("Dragon", r(401...410, 501...511)),
            ]),
        ]),
    ]

    /// Japan has no lot menus yet — the note covers it.
    static func lots(for resort: ParkGroup) -> [ParkingLot] {
        switch resort {
        case .disney:    return disney
        case .universal: return universal
        case .tokyoDisney, .universalJapan: return []
        }
    }

    static func lot(named name: String) -> ParkingLot? {
        (disney + universal).first { $0.name == name }
    }
}

// MARK: - Lot layouts (OpenStreetMap) and row guessing

/// One row line on the ground (a parking aisle), end to end
struct ParkingLine: Equatable {
    let a: CLLocationCoordinate2D
    let b: CLLocationCoordinate2D

    static func == (l: ParkingLine, r: ParkingLine) -> Bool {
        l.a.latitude == r.a.latitude && l.a.longitude == r.a.longitude
            && l.b.latitude == r.b.latitude && l.b.longitude == r.b.longitude
    }
}

/// A section's outline and its row lines in order across the lot (from OpenStreetMap, which has
/// no row numbers — those come from `ParkingLots` rows).
struct ParkingLayout {
    let lot: String
    let section: String
    let outline: [CLLocationCoordinate2D]
    let rowLines: [ParkingLine]
}

enum ParkingLayouts {
    static func P(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static func L(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> ParkingLine {
        ParkingLine(a: P(lat1, lon1), b: P(lat2, lon2))
    }

    static func layout(lot: String, section: String, in presets: [ParkingLayout] = presets) -> ParkingLayout? {
        presets.first { $0.lot == lot && $0.section == section }
    }

    static func layout(containing c: CLLocationCoordinate2D, in presets: [ParkingLayout] = presets) -> ParkingLayout? {
        presets.first { ParkingGeometry.contains($0.outline, c) }
    }
}

/// Flat-earth meters around a point — plenty for a parking lot.
enum ParkingGeometry {
    static func xy(_ p: CLLocationCoordinate2D, origin o: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        (x: (p.longitude - o.longitude) * cos(o.latitude * .pi / 180) * 111_320,
         y: (p.latitude - o.latitude) * 110_540)
    }

    static func contains(_ ring: [CLLocationCoordinate2D], _ p: CLLocationCoordinate2D) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.latitude > p.latitude) != (b.latitude > p.latitude),
               p.longitude < (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Meters from a point to a line segment
    static func distance(_ p: CLLocationCoordinate2D, to line: ParkingLine) -> Double {
        let a = xy(line.a, origin: p), b = xy(line.b, origin: p)
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? max(0, min(1, -(a.x * dx + a.y * dy) / len2)) : 0
        let cx = a.x + t * dx, cy = a.y + t * dy
        return (cx * cx + cy * cy).squareRoot()
    }

    static func meters(_ p: CLLocationCoordinate2D, _ q: CLLocationCoordinate2D) -> Double {
        let d = xy(q, origin: p)
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    static func midpoint(_ line: ParkingLine) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (line.a.latitude + line.b.latitude) / 2,
                               longitude: (line.a.longitude + line.b.longitude) / 2)
    }
}

/// A spot someone saved with GPS and a row — how ThrillTrack learns lots it has no map for, and
/// which way a mapped section's rows are numbered.
struct ParkingSample: Codable, Equatable {
    var lot: String
    /// "" for lots without sections
    var section: String
    var row: String
    var latitude: Double
    var longitude: Double
    var savedAt: Date

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Guesses lot, section and row from where you're standing.
enum ParkingGuess {
    struct Result: Equatable {
        var lot: String?
        var section: String?
        var row: String?
        /// The section came from the lot map (not just past saves)
        var fromMap = false
    }

    /// Saves within this distance count as "this section"
    static let sectionRadius = 150.0
    static let lotRadius = 1500.0

    /// - Parameter parkCoordinate: the park a lot serves — its nearest row line gets the lowest
    ///   number until saved spots show which way the section is numbered
    static func guess(at c: CLLocationCoordinate2D, lots: [ParkingLot], samples: [ParkingSample],
                      presets: [ParkingLayout] = ParkingLayouts.presets,
                      parkCoordinate: (String) -> CLLocationCoordinate2D? = { _ in nil }) -> Result {
        let names = Set(lots.map(\.name))
        let known = samples.filter { names.contains($0.lot) }
        var result = Result()

        if let layout = presets.first(where: { names.contains($0.lot) && ParkingGeometry.contains($0.outline, c) }) {
            result.lot = layout.lot
            result.section = layout.section
            result.fromMap = true
        } else if let nearest = known.min(by: { ParkingGeometry.meters(c, $0.coordinate) < ParkingGeometry.meters(c, $1.coordinate) }) {
            let d = ParkingGeometry.meters(c, nearest.coordinate)
            if d <= lotRadius { result.lot = nearest.lot }
            if d <= sectionRadius { result.section = nearest.section.isEmpty ? nil : nearest.section }
        }

        guard let lotName = result.lot, let lot = lots.first(where: { $0.name == lotName }), !lot.isGarage else {
            return result
        }
        let rows = lot.rows(for: result.section)
        guard !rows.isEmpty else { return result }
        let sectionSamples = known.filter { $0.lot == lotName && $0.section == (result.section ?? "") && rows.contains($0.row) }

        if let section = result.section, let layout = ParkingLayouts.layout(lot: lotName, section: section, in: presets),
           layout.rowLines.count > 1 {
            result.row = mappedRow(at: c, layout: layout, rows: rows, samples: sectionSamples,
                                   park: parkCoordinate(lotName))
        } else {
            result.row = learnedRow(at: c, rows: rows, samples: sectionSamples)
        }
        return result
    }

    /// Nearest row line → its place across the section → a row, numbered in the direction saved
    /// spots agree with (else lowest nearest the park).
    static func mappedRow(at c: CLLocationCoordinate2D, layout: ParkingLayout, rows: [String],
                          samples: [ParkingSample], park: CLLocationCoordinate2D?) -> String? {
        let lines = layout.rowLines
        func lineIndex(_ p: CLLocationCoordinate2D) -> Int {
            lines.indices.min { ParkingGeometry.distance(p, to: lines[$0]) < ParkingGeometry.distance(p, to: lines[$1]) } ?? 0
        }
        func rowIndex(line k: Int, ascending: Bool) -> Int {
            let fraction = Double(k) / Double(lines.count - 1)
            let i = Int((fraction * Double(rows.count - 1)).rounded())
            return ascending ? i : rows.count - 1 - i
        }
        var ascending = true
        let votes = samples.compactMap { s -> (asc: Int, desc: Int)? in
            guard let actual = rows.firstIndex(of: s.row) else { return nil }
            let k = lineIndex(s.coordinate)
            return (asc: abs(rowIndex(line: k, ascending: true) - actual),
                    desc: abs(rowIndex(line: k, ascending: false) - actual))
        }
        if !votes.isEmpty {
            ascending = votes.map(\.asc).reduce(0, +) <= votes.map(\.desc).reduce(0, +)
        } else if let park, let first = lines.first, let last = lines.last {
            ascending = ParkingGeometry.meters(park, ParkingGeometry.midpoint(first))
                <= ParkingGeometry.meters(park, ParkingGeometry.midpoint(last))
        }
        return rows[rowIndex(line: lineIndex(c), ascending: ascending)]
    }

    /// No map: fit rows along the line through past saves (2+ spread out), else the save you're
    /// standing next to.
    static func learnedRow(at c: CLLocationCoordinate2D, rows: [String], samples: [ParkingSample]) -> String? {
        let points = samples.compactMap { s -> (xy: (x: Double, y: Double), index: Int)? in
            rows.firstIndex(of: s.row).map { (xy: ParkingGeometry.xy(s.coordinate, origin: c), index: $0) }
        }
        guard !points.isEmpty else { return nil }
        // Axis through the two saves furthest apart in row number
        let pairs = points.indices.flatMap { i in points.indices.filter { $0 > i }.map { (i, $0) } }
        if let pair = pairs.max(by: { abs(points[$0.0].index - points[$0.1].index) < abs(points[$1.0].index - points[$1.1].index) }) {
            let a = points[pair.0], b = points[pair.1]
            let dx = b.xy.x - a.xy.x, dy = b.xy.y - a.xy.y
            let length = (dx * dx + dy * dy).squareRoot()
            if a.index != b.index, length >= 20 {
                let ux = dx / length, uy = dy / length
                // Least squares: index = alpha + beta * s, s = position along the axis
                let s = points.map { $0.xy.x * ux + $0.xy.y * uy }
                let n = Double(points.count)
                let meanS = s.reduce(0, +) / n
                let meanI = Double(points.map(\.index).reduce(0, +)) / n
                let sxx = s.map { ($0 - meanS) * ($0 - meanS) }.reduce(0, +)
                let sxy = zip(s, points).map { ($0 - meanS) * (Double($1.index) - meanI) }.reduce(0, +)
                guard sxx > 0 else { return nil }
                let beta = sxy / sxx
                let predicted = meanI + beta * (0 - meanS)   // you're at the origin
                let index = max(0, min(rows.count - 1, Int(predicted.rounded())))
                return rows[index]
            }
        }
        // Right next to a spot saved before
        if let near = points.min(by: { hypot($0.xy.x, $0.xy.y) < hypot($1.xy.x, $1.xy.y) }),
           hypot(near.xy.x, near.xy.y) <= 40 {
            return rows[near.index]
        }
        return nil
    }
}

// MARK: - Distance

enum ParkingDistance {
    /// Lots and garages are a straighter walk than park paths
    static let pathFactor = 1.2
    static let metersPerMinute = WalkEstimate.metersPerMinute
    /// Past this you're not walking back to the car — just show the distance
    static let maxWalkMeters = 5000.0

    static func meters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    static func walkMinutes(meters: Double) -> Int? {
        guard meters <= maxWalkMeters else { return nil }
        return max(1, Int((meters * pathFactor / metersPerMinute).rounded()))
    }

    /// "0.4 mi · about 8 min walk" (units follow the phone's region)
    static func describe(meters: Double, locale: Locale = .current) -> String {
        let distance = Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(locale))
        guard let minutes = walkMinutes(meters: meters) else { return distance }
        return "\(distance) · about \(minutes) min walk"
    }
}

// MARK: - Service

@Observable
final class ParkingService {
    static let shared = ParkingService()

    private static let storageKey = "parkingSpots"
    private let icloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// Every saved spot, keyed by resort raw value (current or not)
    private(set) var spots: [String: ParkingSpot] = [:]
    /// Bumped when a photo changes so views reload it
    private(set) var photoVersion = 0
    /// Your saves with GPS + row (iCloud-synced) — they teach the row guess (`ParkingGuess`)
    private(set) var samples: [ParkingSample] = []
    /// Everyone's anonymous samples from the ThrillTrack server, by resort raw value
    private(set) var sharedSamples: [String: [ParkingSample]] = [:]
    private var sharedFetchedAt: [String: Date] = [:]
    private static let samplesKey = "parkingSamples"
    static let maxSamples = 300
    /// Send anonymous row positions to the server so everyone's guesses get better
    static let shareKey = "shareParkingLayouts"
    static var sharingEnabled: Bool { UserDefaults.standard.object(forKey: shareKey) as? Bool ?? true }

    private init() {
        spots = Self.decode(icloud.data(forKey: Self.storageKey) ?? defaults.data(forKey: Self.storageKey))
        samples = Self.decodeSamples(icloud.data(forKey: Self.samplesKey) ?? defaults.data(forKey: Self.samplesKey))
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Another device saved or cleared a spot
            self.spots = Self.decode(self.icloud.data(forKey: Self.storageKey))
            self.samples = Self.decodeSamples(self.icloud.data(forKey: Self.samplesKey))
        }
    }

    /// Today's spot at this resort, if any
    func spot(for resort: ParkGroup, now: Date = .now) -> ParkingSpot? {
        guard let spot = spots[resort.rawValue], spot.isCurrent(now: now) else { return nil }
        return spot
    }

    func save(coordinate: CLLocationCoordinate2D?, note: String, details: ParkingDetails = .empty,
              resort: ParkGroup) {
        var spot = ParkingSpot(latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                               note: note, resortRaw: resort.rawValue, savedAt: .now)
        spot.details = details.normalized
        spots[resort.rawValue] = spot
        persist()
        recordSample(from: spot, resort: resort)
    }

    func updateDetails(_ details: ParkingDetails, resort: ParkGroup) {
        guard var spot = spot(for: resort) else { return }
        spot.details = details.normalized
        spots[resort.rawValue] = spot
        persist()
        recordSample(from: spot, resort: resort)
    }

    func updateNote(_ note: String, resort: ParkGroup) {
        guard var spot = spot(for: resort) else { return }
        spot.note = note
        spots[resort.rawValue] = spot
        persist()
    }

    func updateLocation(_ coordinate: CLLocationCoordinate2D, resort: ParkGroup) {
        guard var spot = spot(for: resort) else {
            save(coordinate: coordinate, note: "", resort: resort)
            return
        }
        spot.latitude = coordinate.latitude
        spot.longitude = coordinate.longitude
        spots[resort.rawValue] = spot
        persist()
        recordSample(from: spot, resort: resort)
    }

    // MARK: Samples (row guessing)

    /// Your saves plus everyone's shared ones for a resort
    func allSamples(for resort: ParkGroup) -> [ParkingSample] {
        samples + (sharedSamples[resort.rawValue] ?? [])
    }

    /// A spot with GPS and a real row (one from the lot's list) teaches the guess. Edits to the
    /// same spot replace its sample.
    private func recordSample(from spot: ParkingSpot, resort: ParkGroup) {
        guard let sample = Self.sample(from: spot) else { return }
        let changed = !samples.contains(sample)
        samples.removeAll { $0.savedAt == spot.savedAt }
        samples.append(sample)
        if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
        persistSamples()
        if changed, Self.sharingEnabled { Task { await Self.upload(sample, resort: resort) } }
    }

    static func sample(from spot: ParkingSpot) -> ParkingSample? {
        guard let c = spot.coordinate, let lotName = spot.lot, let row = spot.row,
              let lot = ParkingLots.lot(named: lotName), !lot.isGarage,
              lot.rows(for: spot.section).contains(row) else { return nil }
        return ParkingSample(lot: lotName, section: spot.section ?? "", row: row,
                             latitude: c.latitude, longitude: c.longitude, savedAt: spot.savedAt)
    }

    private func persistSamples() {
        if let data = try? JSONEncoder().encode(samples) {
            icloud.set(data, forKey: Self.samplesKey)
            defaults.set(data, forKey: Self.samplesKey)
        }
    }

    static func decodeSamples(_ data: Data?) -> [ParkingSample] {
        data.flatMap { try? JSONDecoder().decode([ParkingSample].self, from: $0) } ?? []
    }

    private struct SharedResponse: Decodable {
        struct Row: Decodable { let lot: String; let section: String; let row: String; let latitude: Double; let longitude: Double }
        let samples: [Row]
    }

    /// Everyone's samples for the resort (at most every 6 hours)
    @MainActor
    func refreshShared(resort: ParkGroup) async {
        if let at = sharedFetchedAt[resort.rawValue], Date.now.timeIntervalSince(at) < 6 * 3600 { return }
        guard let url = ThrillTrackServer.url("v1/parking/samples",
                                              query: [URLQueryItem(name: "resort", value: resort.apiSlug)]) else { return }
        let result = try? await URLSession.shared.data(from: url)
        guard let result, (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SharedResponse.self, from: result.0) else { return }
        sharedFetchedAt[resort.rawValue] = .now
        sharedSamples[resort.rawValue] = decoded.samples.map {
            ParkingSample(lot: $0.lot, section: $0.section, row: $0.row, latitude: $0.latitude,
                          longitude: $0.longitude, savedAt: .distantPast)
        }
    }

    @MainActor
    private static func upload(_ sample: ParkingSample, resort: ParkGroup) async {
        guard let url = ThrillTrackServer.url("v1/parking/sample", query: []) else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["resort": resort.apiSlug, "lot": sample.lot, "section": sample.section,
                                   "row": sample.row, "latitude": sample.latitude, "longitude": sample.longitude]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    func clear(resort: ParkGroup) {
        spots[resort.rawValue] = nil
        setPhoto(nil, resort: resort)
        persist()
    }

    // MARK: Photo (this device only)

    private func photoURL(for resort: ParkGroup) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Parking", directoryHint: .isDirectory) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(RideMetadata.normalize(resort.rawValue)).jpg")
    }

    func photo(for resort: ParkGroup) -> UIImage? {
        _ = photoVersion   // observed, so views refresh when it changes
        guard spot(for: resort) != nil, let url = photoURL(for: resort),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func setPhoto(_ image: UIImage?, resort: ParkGroup) {
        guard let url = photoURL(for: resort) else { return }
        if let data = image.flatMap(Self.jpeg) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        photoVersion += 1
    }

    /// Shrinks to ~1600 px so a row-sign photo stays small
    private static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        guard scale < 1 else { return image.jpegData(compressionQuality: 0.7) }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }

    // MARK: Directions

    /// Apple Maps walking directions to the car
    static func openWalkingDirections(to spot: ParkingSpot) {
        guard let coordinate = spot.coordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = spot.summary.isEmpty ? "My Car" : "My Car — \(spot.summary)"
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    // MARK: Storage

    private func persist() {
        let data = Self.encode(spots)
        icloud.set(data, forKey: Self.storageKey)
        defaults.set(data, forKey: Self.storageKey)
    }

    static func encode(_ spots: [String: ParkingSpot]) -> Data? {
        try? JSONEncoder().encode(spots)
    }

    static func decode(_ data: Data?) -> [String: ParkingSpot] {
        guard let data, let spots = try? JSONDecoder().decode([String: ParkingSpot].self, from: data) else { return [:] }
        return spots
    }
}

// MARK: - Precise one-shot location

/// The map's location updates are coarse (100 m) to save battery; saving a car needs a
/// real fix. Collects updates for a few seconds and returns the most accurate one.
@MainActor
final class PreciseLocator: NSObject, CLLocationManagerDelegate {
    enum Failure: Error { case denied, unavailable }

    private let manager = CLLocationManager()
    private var best: CLLocation?
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeout: Task<Void, Never>?

    /// Good enough to stop early
    static let targetAccuracy: CLLocationAccuracy = 15

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func locate(timeout seconds: Double = 8) async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted: throw Failure.denied
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.startUpdatingLocation()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.finish()
            }
        }
    }

    private func finish(error: Error? = nil) {
        manager.stopUpdatingLocation()
        timeout?.cancel()
        guard let continuation else { return }
        self.continuation = nil
        if let best { continuation.resume(returning: best) }
        else { continuation.resume(throwing: error ?? Failure.unavailable) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations where location.horizontalAccuracy >= 0 {
                if self.best == nil || location.horizontalAccuracy < self.best!.horizontalAccuracy {
                    self.best = location
                }
            }
            if let best = self.best, best.horizontalAccuracy <= Self.targetAccuracy { self.finish() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if (error as? CLError)?.code == .denied { self.finish(error: Failure.denied) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted { self.finish(error: Failure.denied) }
        }
    }
}

// MARK: - Park-close reminder

/// "Parks close at 9:00 PM — your car is at Zurg 112." Fires a little before the last park
/// at the resort closes, while a spot is saved. Rescheduled whenever schedules load.
enum ParkingReminder {
    static let lead: TimeInterval = 30 * 60
    static let enabledKey = "parkingCloseReminder"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func identifier(for resort: ParkGroup) -> String {
        "parking-close-\(RideMetadata.normalize(resort.rawValue))"
    }

    /// Latest regular closing today minus `lead`; nil once that's passed. Ticketed events
    /// (after-hours parties) don't count — most guests leave at the regular close. Pure.
    static func fireDate(schedule: [ParkScheduleDay], now: Date = .now) -> (fire: Date, closing: Date)? {
        let closings = schedule.filter { !$0.isTicketedEvent }.compactMap(\.closingDate)
        guard let closing = closings.max() else { return nil }
        let fire = closing.addingTimeInterval(-lead)
        return fire > now ? (fire, closing) : nil
    }

    /// Schedules (or replaces) the reminder for today's spot, or removes it if there's nothing to remind.
    static func refresh(resort: ParkGroup, schedule: [ParkScheduleDay]) {
        let center = UNUserNotificationCenter.current()
        let id = identifier(for: resort)
        guard isEnabled, let spot = ParkingService.shared.spot(for: resort),
              let when = fireDate(schedule: schedule) else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            return
        }
        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive
        content.title = "🚗 Parks close at \(when.closing.formatted(date: .omitted, time: .shortened))"
        content.body = spot.summary.isEmpty
            ? "Tap for walking directions back to your car."
            : "Your car: \(spot.summary). Tap for walking directions."
        content.sound = .default
        content.userInfo = [DeepLink.userInfoKey: DeepLink.parking.url.absoluteString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, when.fire.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(resort: ParkGroup) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: resort)])
    }
}

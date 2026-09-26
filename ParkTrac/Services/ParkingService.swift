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

struct ParkingLot: Identifiable, Equatable {
    struct Group: Equatable {
        /// "Heroes", "Villains", "North Garage"… (nil = one plain list)
        var name: String?
        var sections: [String]
    }

    var name: String
    var groups: [Group]
    /// Garages with numbered levels (Disney Springs)
    var levels: ClosedRange<Int>? = nil
    /// "Row" on Disney lots; empty where the sign shows a bare number (Universal "King Kong 410")
    var rowLabel: String = "Row"
    var rowPrompt: String = "e.g. 112"

    var id: String { name }
    var allSections: [String] { groups.flatMap(\.sections) }
}

/// Section names from the parks' signage (compiled Sept 2026 — lots get renamed now and then;
/// "Other" + the note covers anything missing).
enum ParkingLots {
    static let disney: [ParkingLot] = [
        ParkingLot(name: "Magic Kingdom", groups: [
            .init(name: "Heroes", sections: ["Aladdin", "Mulan", "Peter Pan", "Rapunzel", "Simba", "Woody"]),
            .init(name: "Villains", sections: ["Cruella", "Hook", "Jafar", "Scar", "Ursula", "Zurg"]),
        ]),
        ParkingLot(name: "EPCOT", groups: [
            .init(name: "Earth", sections: ["Crush", "Dory", "HeiHei", "Moana"]),
            .init(name: "Space", sections: ["Eve", "Gamora", "Rocket", "WALL-E"]),
        ]),
        ParkingLot(name: "Hollywood Studios", groups: [
            .init(name: nil, sections: ["BB-8", "Buzz", "Jessie", "Mickey", "Minnie", "Olaf", "Woody"]),
        ]),
        ParkingLot(name: "Animal Kingdom", groups: [
            .init(name: nil, sections: ["Butterfly", "Dinosaur", "Giraffe", "Peacock", "Unicorn", "Yeti"]),
        ]),
        ParkingLot(name: "Disney Springs", groups: [
            .init(name: nil, sections: ["Orange Garage", "Lime Garage", "Grapefruit Garage"]),
        ], levels: 1...7, rowLabel: "Row", rowPrompt: "Optional"),
    ]

    static let universal: [ParkingLot] = [
        ParkingLot(name: "CityWalk Garages", groups: [
            .init(name: "North Garage", sections: ["Jurassic Park", "King Kong", "Jaws"]),
            .init(name: "South Garage", sections: ["E.T.", "Spider-Man", "Cat in the Hat"]),
        ], rowLabel: "", rowPrompt: "Number on the sign, e.g. 410"),
        ParkingLot(name: "Epic Universe", groups: [
            .init(name: nil, sections: ["Explorer", "Gamer", "Hero", "Monster", "Viking"]),
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

    private init() {
        spots = Self.decode(icloud.data(forKey: Self.storageKey) ?? defaults.data(forKey: Self.storageKey))
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Another device saved or cleared a spot
            self.spots = Self.decode(self.icloud.data(forKey: Self.storageKey))
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
    }

    func updateDetails(_ details: ParkingDetails, resort: ParkGroup) {
        guard var spot = spot(for: resort) else { return }
        spot.details = details.normalized
        spots[resort.rawValue] = spot
        persist()
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

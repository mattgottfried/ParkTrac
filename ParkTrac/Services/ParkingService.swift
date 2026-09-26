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

    /// "Zurg 112" or "Parking spot"
    var title: String { trimmedNote.isEmpty ? "Parking spot" : trimmedNote }
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

    func save(coordinate: CLLocationCoordinate2D?, note: String, resort: ParkGroup) {
        spots[resort.rawValue] = ParkingSpot(latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                                            note: note, resortRaw: resort.rawValue, savedAt: .now)
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
        item.name = spot.trimmedNote.isEmpty ? "My Car" : "My Car — \(spot.trimmedNote)"
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
        content.body = spot.trimmedNote.isEmpty
            ? "Tap for walking directions back to your car."
            : "Your car: \(spot.trimmedNote). Tap for walking directions."
        content.sound = .default
        content.userInfo = [DeepLink.userInfoKey: DeepLink.parking.url.absoluteString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, when.fire.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(resort: ParkGroup) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: resort)])
    }
}

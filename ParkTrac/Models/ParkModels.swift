import Foundation
import CoreLocation
import SwiftUI

// MARK: - Crowd Level

enum CrowdLevel: String {
    case ghost    = "Ghost Town"
    case low      = "Low"
    case moderate = "Moderate"
    case high     = "High"
    case veryHigh = "Very High"

    static func from(averageWait: Double) -> CrowdLevel {
        switch averageWait {
        case ..<5:  return .ghost
        case ..<20: return .low
        case ..<40: return .moderate
        case ..<60: return .high
        default:    return .veryHigh
        }
    }

    var color: Color {
        switch self {
        case .ghost, .low: return .green
        case .moderate:    return .yellow
        case .high:        return .orange
        case .veryHigh:    return .red
        }
    }

    var systemImage: String {
        switch self {
        case .ghost:    return "person"
        case .low:      return "person"
        case .moderate: return "person.2"
        case .high:     return "person.3"
        case .veryHigh: return "person.3.fill"
        }
    }
}

// MARK: - Destination Children

struct DestinationChildrenResponse: Codable {
    let id: String
    let name: String
    let entityType: String
    let children: [ParkEntity]
}

struct ParkEntity: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let entityType: String
    let location: LocationData?

    var coordinate: CLLocationCoordinate2D? {
        guard let loc = location else { return nil }
        return CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
    }
}

struct LocationData: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Attraction Children

struct ParkChildrenResponse: Codable {
    let id: String
    let name: String
    let entityType: String
    let children: [AttractionEntity]
}

struct AttractionEntity: Codable, Identifiable {
    let id: String
    let name: String
    let entityType: String
    let location: LocationData?

    var coordinate: CLLocationCoordinate2D? {
        guard let loc = location else { return nil }
        return CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
    }
}

// MARK: - Live Data

struct LiveDataResponse: Codable {
    let liveData: [LiveDataEntry]
}

struct LiveDataEntry: Codable, Identifiable {
    let id: String
    let name: String
    let entityType: String
    let status: String?
    let queue: QueueData?
    let showtimes: [Showtime]?

    var waitMinutes: Int? { queue?.STANDBY?.waitTime }
    var isOperating: Bool { status == "OPERATING" }

    var statusDisplay: String {
        switch status {
        case "OPERATING":     return "Operating"
        case "CLOSED":        return "Closed"
        case "DOWN":          return "Down"
        case "REFURBISHMENT": return "Refurbishment"
        default:              return status ?? "Unknown"
        }
    }
}

struct QueueData: Codable {
    let STANDBY: StandbyQueue?
    /// Lightning Lane Multi Pass (Disney) — next available return window
    let RETURN_TIME: ReturnTimeQueue?
    /// Lightning Lane Single Pass (Disney) — next return window plus price
    let PAID_RETURN_TIME: ReturnTimeQueue?
}

struct StandbyQueue: Codable {
    let waitTime: Int?
}

/// themeparks.wiki return-time queue. `state` is AVAILABLE, TEMP_FULL or FINISHED.
struct ReturnTimeQueue: Codable {
    let state: String?
    let returnStart: String?
    let returnEnd: String?
    let price: ReturnTimePrice?
}

struct ReturnTimePrice: Codable {
    let amount: Double?
    let currency: String?
    let formatted: String?
}

/// Parsed Lightning Lane availability for one queue type.
struct LightningLaneInfo: Equatable {
    enum State: Equatable { case available, temporarilyFull, soldOut, unknown }

    let state: State
    let returnStart: Date?
    let returnEnd: Date?
    /// Single Pass price, e.g. "$15.00" (nil for Multi Pass)
    let price: String?

    var isAvailable: Bool { state == .available && returnStart != nil }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoFrac.date(from: s)
    }

    init?(_ queue: ReturnTimeQueue?) {
        guard let queue else { return nil }
        switch queue.state {
        case "AVAILABLE": state = .available
        case "TEMP_FULL": state = .temporarilyFull
        case "FINISHED":  state = .soldOut
        default:          state = .unknown
        }
        returnStart = Self.date(queue.returnStart)
        returnEnd = Self.date(queue.returnEnd)
        if let formatted = queue.price?.formatted, !formatted.isEmpty {
            price = formatted
        } else if let cents = queue.price?.amount {
            price = (cents / 100).formatted(.currency(code: queue.price?.currency ?? "USD"))
        } else {
            price = nil
        }
    }

    /// Short text for cards, e.g. "LL 1:35 PM", "LL full", "LL sold out".
    var shortText: String { shortText(prefix: "LL") }

    /// `prefix` is the resort's abbreviation ("LL" Orlando, "PP" Tokyo Priority Pass).
    func shortText(prefix: String) -> String {
        switch state {
        case .available:
            guard let start = returnStart else { return "\(prefix) available" }
            return "\(prefix) \(start.formatted(date: .omitted, time: .shortened))"
        case .temporarilyFull: return "\(prefix) full for now"
        case .soldOut:         return "\(prefix) sold out"
        case .unknown:         return prefix
        }
    }
}

// MARK: - Show / Entertainment

struct Showtime: Codable {
    let startTime: String?   // ISO8601 string from API
    let endTime: String?
    let type: String?

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let formatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var startDate: Date? {
        guard let s = startTime else { return nil }
        return Self.formatter.date(from: s) ?? Self.formatterNoFrac.date(from: s)
    }

    var endDate: Date? {
        guard let s = endTime else { return nil }
        return Self.formatter.date(from: s) ?? Self.formatterNoFrac.date(from: s)
    }
}

struct DisplayShow: Identifiable {
    let id: String
    let name: String
    let parkId: String
    let status: String
    let showtimes: [Showtime]

    var nextShowtime: Date? {
        let now = Date()
        return showtimes.compactMap(\.startDate).filter { $0 > now }.min()
    }

    var isOperating: Bool { status == "OPERATING" }

    var statusDisplay: String {
        switch status {
        case "OPERATING": return "Operating"
        case "CLOSED":    return "Closed"
        case "DOWN":      return "Down"
        default:          return status
        }
    }

    init(live: LiveDataEntry, parkId: String) {
        self.id        = live.id
        self.name      = live.name
        self.parkId    = parkId
        self.status    = live.status ?? "CLOSED"
        self.showtimes = live.showtimes ?? []
    }
}

// MARK: - Park Schedule

struct ScheduleResponse: Codable {
    let schedule: [ParkScheduleDay]
}

struct ParkScheduleDay: Codable, Identifiable {
    let date: String
    let openingTime: String?
    let closingTime: String?
    let type: String?
    /// Event name from the API when it has one, e.g. "Mickey's Not-So-Scary Halloween Party"
    /// or "Early Theme Park Entry". Optional — absent for plain operating hours.
    let description: String?

    // Opening time included so two events on the same day don't collide
    var id: String { date + (type ?? "") + (openingTime ?? "") }

    /// The API's name for this entry, if it's non-empty.
    var eventName: String? {
        guard let name = description?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let formatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var openingDate: Date? {
        guard let s = openingTime else { return nil }
        return Self.formatter.date(from: s) ?? Self.formatterNoFrac.date(from: s)
    }

    var closingDate: Date? {
        guard let s = closingTime else { return nil }
        return Self.formatter.date(from: s) ?? Self.formatterNoFrac.date(from: s)
    }

    var isExtraHours: Bool { type == "EXTRA_HOURS" }
    var isTicketedEvent: Bool { type == "TICKETED_EVENT" }
}

// MARK: - Display Model (live data + GPS merged)

struct DisplayRide: Identifiable {
    let id: String
    let name: String
    let status: String?
    let waitMinutes: Int?
    let isOperating: Bool
    let coordinate: CLLocationCoordinate2D?
    let parkId: String
    /// Lightning Lane Multi Pass next return (Disney only; nil if the ride has none)
    let multiPass: LightningLaneInfo?
    /// Lightning Lane Single Pass next return + price
    let singlePass: LightningLaneInfo?

    var statusDisplay: String {
        switch status {
        case "OPERATING":     return "Operating"
        case "CLOSED":        return "Closed"
        case "DOWN":          return "Down"
        case "REFURBISHMENT": return "Refurbishment"
        default:              return status ?? "Unknown"
        }
    }

    /// VoiceOver phrasing of the wait/status (map pins and ride cards).
    var spokenStatus: String {
        if status == "DOWN" { return "Temporarily down" }
        guard isOperating else { return statusDisplay }
        guard let minutes = waitMinutes else { return "Open, no posted wait" }
        return minutes == 1 ? "1 minute wait" : "\(minutes) minute wait"
    }

    init(live: LiveDataEntry, parkId: String, location: CLLocationCoordinate2D?) {
        self.id = live.id
        self.name = live.name
        self.status = live.status
        self.waitMinutes = live.waitMinutes
        self.isOperating = live.isOperating
        self.coordinate = location
        self.parkId = parkId
        self.multiPass = LightningLaneInfo(live.queue?.RETURN_TIME)
        self.singlePass = LightningLaneInfo(live.queue?.PAID_RETURN_TIME)
    }

    /// A ride known from the daily catalog but absent from live data
    /// (park closed, or the API dropped it overnight) — shown as Closed.
    init(catalogId: String, name: String, parkId: String, location: CLLocationCoordinate2D?) {
        self.id = catalogId
        self.name = name
        self.status = "CLOSED"
        self.waitMinutes = nil
        self.isOperating = false
        self.coordinate = location
        self.parkId = parkId
        self.multiPass = nil
        self.singlePass = nil
    }
}

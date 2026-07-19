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
        case .ghost:    return .teal
        case .low:      return .green
        case .moderate: return .yellow
        case .high:     return .orange
        case .veryHigh: return .red
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
}

struct StandbyQueue: Codable {
    let waitTime: Int?
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

    var id: String { date + (type ?? "") }

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

    var statusDisplay: String {
        switch status {
        case "OPERATING":     return "Operating"
        case "CLOSED":        return "Closed"
        case "DOWN":          return "Down"
        case "REFURBISHMENT": return "Refurbishment"
        default:              return status ?? "Unknown"
        }
    }

    init(live: LiveDataEntry, parkId: String, location: CLLocationCoordinate2D?) {
        self.id = live.id
        self.name = live.name
        self.status = live.status
        self.waitMinutes = live.waitMinutes
        self.isOperating = live.isOperating
        self.coordinate = location
        self.parkId = parkId
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
    }
}

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
}

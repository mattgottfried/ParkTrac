import Foundation
import CoreLocation

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

    var statusDisplay: String {
        switch status {
        case "OPERATING":     return "Operating"
        case "CLOSED":        return "Closed"
        case "DOWN":          return "Down"
        case "REFURBISHMENT": return "Refurbishment"
        default:              return status ?? "Unknown"
        }
    }

    init(live: LiveDataEntry, location: CLLocationCoordinate2D?) {
        self.id = live.id
        self.name = live.name
        self.status = live.status
        self.waitMinutes = live.waitMinutes
        self.isOperating = live.isOperating
        self.coordinate = location
    }
}

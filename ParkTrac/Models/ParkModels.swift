import Foundation

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
        case "OPERATING": return "Operating"
        case "CLOSED": return "Closed"
        case "DOWN": return "Down"
        case "REFURBISHMENT": return "Refurbishment"
        default: return status ?? "Unknown"
        }
    }
}

struct QueueData: Codable {
    let STANDBY: StandbyQueue?
}

struct StandbyQueue: Codable {
    let waitTime: Int?
}

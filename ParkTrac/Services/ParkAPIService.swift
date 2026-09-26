import Foundation

enum ParkAPIError: LocalizedError {
    case badResponse(Int)
    case decodingFailed(Error)
    case destinationNotFound(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Server returned status \(code)"
        case .decodingFailed(let err): return "Failed to decode response: \(err.localizedDescription)"
        case .destinationNotFound(let name): return "Couldn't find \(name) in the park data service"
        }
    }
}

actor ParkAPIService {
    static let shared = ParkAPIService()
    private let base = URL(string: "https://api.themeparks.wiki/v1")!
    private let decoder = JSONDecoder()

    func fetchLiveData(for parkId: String) async throws -> [LiveDataEntry] {
        let url = base.appendingPathComponent("entity/\(parkId)/live")
        let data = try await get(url)
        do {
            return try decoder.decode(LiveDataResponse.self, from: data).liveData
        } catch {
            throw ParkAPIError.decodingFailed(error)
        }
    }

    /// Parks for a resort. Orlando uses its hardcoded destination UUID; Japan's destination
    /// is found in `GET /destinations` (loose slug/name match, like the official JS client)
    /// and its parks come from `/entity/{id}/children`, falling back to the park list that
    /// `/destinations` itself includes.
    func fetchParks(for group: ParkGroup) async throws -> [ParkEntity] {
        if let id = group.destinationId {
            return try await fetchDestinationChildren(destinationId: id)
        }
        let destination = try await findDestination(for: group)
        if let parks = try? await fetchDestinationChildren(destinationId: destination.id), !parks.isEmpty {
            return parks
        }
        let listed = (destination.parks ?? []).map {
            ParkEntity(id: $0.id, name: $0.name, entityType: "PARK", location: nil)
        }
        guard !listed.isEmpty else { throw ParkAPIError.destinationNotFound(group.rawValue) }
        return listed
    }

    /// Looked-up destinations, kept for the session (one /destinations call per launch)
    private var destinationCache: [ParkGroup: DestinationsResponse.Destination] = [:]

    private func findDestination(for group: ParkGroup) async throws -> DestinationsResponse.Destination {
        if let cached = destinationCache[group] { return cached }
        let data = try await get(base.appendingPathComponent("destinations"))
        let list: [DestinationsResponse.Destination]
        do {
            list = try decoder.decode(DestinationsResponse.self, from: data).destinations
        } catch {
            throw ParkAPIError.decodingFailed(error)
        }
        guard let match = DestinationsResponse.match(list, for: group) else {
            throw ParkAPIError.destinationNotFound(group.rawValue)
        }
        destinationCache[group] = match
        return match
    }

    func fetchDestinationChildren(destinationId: String) async throws -> [ParkEntity] {
        let url = base.appendingPathComponent("entity/\(destinationId)/children")
        let data = try await get(url)
        do {
            let response = try decoder.decode(DestinationChildrenResponse.self, from: data)
            return response.children.filter { $0.entityType == "PARK" }
        } catch {
            throw ParkAPIError.decodingFailed(error)
        }
    }

    func fetchAttractionChildren(parkId: String) async throws -> [AttractionEntity] {
        let url = base.appendingPathComponent("entity/\(parkId)/children")
        let data = try await get(url)
        do {
            let response = try decoder.decode(ParkChildrenResponse.self, from: data)
            return response.children.filter { $0.entityType == "ATTRACTION" }
        } catch {
            throw ParkAPIError.decodingFailed(error)
        }
    }

    func fetchSchedule(parkId: String) async throws -> [ParkScheduleDay] {
        let url = base.appendingPathComponent("entity/\(parkId)/schedule")
        let data = try await get(url)
        do {
            return try decoder.decode(ScheduleResponse.self, from: data).schedule
        } catch {
            throw ParkAPIError.decodingFailed(error)
        }
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ParkAPIError.badResponse(code)
        }
        return data
    }
}

/// `GET /destinations` — every resort themeparks.wiki covers.
struct DestinationsResponse: Codable {
    struct Park: Codable {
        let id: String
        let name: String
    }
    struct Destination: Codable {
        let id: String
        let name: String
        let slug: String?
        let parks: [Park]?
    }
    let destinations: [Destination]

    /// Loose, case/punctuation-insensitive match: exact slug first, then any slug or name
    /// containing one of the resort's keywords. Pure — unit tested.
    static func match(_ list: [Destination], for group: ParkGroup) -> Destination? {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let slug = norm(group.apiSlug)
        if let exact = list.first(where: { norm($0.slug ?? "") == slug }) { return exact }
        let keys = group.apiNameKeywords.map(norm)
        return list.first { dest in
            let hay = norm(dest.slug ?? "") + " " + norm(dest.name)
            return keys.contains { hay.contains($0) }
        }
    }
}

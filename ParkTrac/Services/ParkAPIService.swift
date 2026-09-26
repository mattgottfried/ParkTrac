import Foundation

enum ParkAPIError: LocalizedError {
    case badResponse(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Server returned status \(code)"
        case .decodingFailed(let err): return "Failed to decode response: \(err.localizedDescription)"
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

    /// Parks for a resort. Orlando uses its hardcoded destination UUID; Japan's UUIDs are
    /// looked up once from `/destinations` (by slug, then name) and cached.
    func fetchParks(for group: ParkGroup) async throws -> [ParkEntity] {
        if let id = group.destinationId {
            return try await fetchDestinationChildren(destinationId: id)
        }
        if let id = try? await resolveDestinationId(for: group) {
            return try await fetchDestinationChildren(destinationId: id)
        }
        // Last resort: the API may accept the slug directly
        return try await fetchDestinationChildren(destinationId: group.apiSlug)
    }

    private func resolveDestinationId(for group: ParkGroup) async throws -> String? {
        let cacheKey = "destinationId_\(group.apiSlug)"
        if let cached = UserDefaults.standard.string(forKey: cacheKey) { return cached }

        let data = try await get(base.appendingPathComponent("destinations"))
        let destinations = try decoder.decode(DestinationsResponse.self, from: data).destinations
        let match = destinations.first { $0.slug == group.apiSlug }
            ?? destinations.first { dest in
                group.apiNameKeywords.contains { dest.name.lowercased().contains($0) }
            }
        if let id = match?.id {
            UserDefaults.standard.set(id, forKey: cacheKey)
        }
        return match?.id
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
    struct Destination: Codable {
        let id: String
        let name: String
        let slug: String?
    }
    let destinations: [Destination]
}

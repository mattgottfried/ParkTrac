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
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ParkAPIError.badResponse(code)
        }
        do {
            return try decoder.decode(LiveDataResponse.self, from: data).liveData
        } catch {
            throw ParkAPIError.decodingFailed(error)
        }
    }
}

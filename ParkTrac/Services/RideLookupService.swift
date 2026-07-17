import Foundation

/// One-shot ride wait time lookup used by Siri/Shortcuts (see RideWaitTimeIntent).
/// Self-contained: no dependency on WaitTimesViewModel or app UI state, since App
/// Intents can run without any of the app's views ever appearing.
struct RideWaitLookup {
    let name: String
    let parkName: String
    let status: String?
    let waitMinutes: Int?

    var isOperating: Bool { status == "OPERATING" }
}

enum RideLookupService {
    static func findRide(named query: String) async -> RideWaitLookup? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for group in ParkGroup.allCases {
            guard let parks = try? await ParkAPIService.shared.fetchDestinationChildren(destinationId: group.destinationId) else { continue }
            for park in parks {
                guard let liveEntries = try? await ParkAPIService.shared.fetchLiveData(for: park.id) else { continue }
                if let entry = liveEntries.first(where: {
                    $0.entityType == "ATTRACTION" && $0.name.localizedCaseInsensitiveContains(trimmed)
                }) {
                    return RideWaitLookup(name: entry.name, parkName: park.name, status: entry.status, waitMinutes: entry.waitMinutes)
                }
            }
        }
        return nil
    }
}

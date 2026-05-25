import Foundation
import Observation

@Observable
final class WaitTimesViewModel {
    var selectedGroup: ParkGroup = .disney {
        didSet {
            selectedPark = selectedGroup.parks[0]
        }
    }
    var selectedPark: Park = ParkGroup.disney.parks[0] {
        didSet { Task { await loadRides() } }
    }
    var rides: [LiveDataEntry] = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
    var lastRefreshed: Date?

    private var refreshTask: Task<Void, Never>?

    var filteredRides: [LiveDataEntry] {
        rides
            .filter { $0.entityType == "ATTRACTION" }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { lhs, rhs in
                if lhs.isOperating != rhs.isOperating { return lhs.isOperating }
                return (lhs.waitMinutes ?? -1) > (rhs.waitMinutes ?? -1)
            }
    }

    @MainActor
    func loadRides() async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await ParkAPIService.shared.fetchLiveData(for: selectedPark.id)
            rides = data
            lastRefreshed = .now
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled {
                    await loadRides()
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

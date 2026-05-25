import Foundation
import CoreLocation
import Observation

@Observable
final class WaitTimesViewModel {
    var selectedGroup: ParkGroup = .disney {
        didSet {
            let parks = parksByGroup[selectedGroup] ?? []
            if let first = parks.first {
                selectedPark = first
            } else {
                selectedPark = nil
                Task { await loadParksIfNeeded(for: selectedGroup) }
            }
        }
    }
    var selectedPark: ParkEntity? {
        didSet { Task { await loadRidesAndLocations() } }
    }

    var parksByGroup: [ParkGroup: [ParkEntity]] = [:]
    var currentParks: [ParkEntity] { parksByGroup[selectedGroup] ?? [] }

    private var attractionLocations: [String: CLLocationCoordinate2D] = [:]
    var rides: [DisplayRide] = []
    var isLoading = false
    var isLoadingParks = false
    var errorMessage: String?
    var searchText = ""
    var lastRefreshed: Date?

    private var refreshTask: Task<Void, Never>?
    var currentParkId: String = ""

    var filteredRides: [DisplayRide] {
        rides
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { lhs, rhs in
                if lhs.isOperating != rhs.isOperating { return lhs.isOperating }
                return (lhs.waitMinutes ?? -1) > (rhs.waitMinutes ?? -1)
            }
    }

    var ridesWithLocation: [DisplayRide] {
        filteredRides.filter { $0.coordinate != nil }
    }

    var selectedParkCoordinate: CLLocationCoordinate2D? {
        selectedPark?.coordinate
    }

    @MainActor
    func loadAllParks() async {
        await withTaskGroup(of: Void.self) { group in
            for parkGroup in ParkGroup.allCases {
                group.addTask { await self.loadParksIfNeeded(for: parkGroup) }
            }
        }
        if selectedPark == nil, let first = parksByGroup[selectedGroup]?.first {
            selectedPark = first
        }
    }

    @MainActor
    func loadParksIfNeeded(for group: ParkGroup) async {
        guard parksByGroup[group] == nil else { return }
        isLoadingParks = true
        do {
            let parks = try await ParkAPIService.shared.fetchDestinationChildren(destinationId: group.destinationId)
            parksByGroup[group] = parks
            if group == selectedGroup && selectedPark == nil {
                selectedPark = parks.first
            }
        } catch {
            errorMessage = "Could not load parks: \(error.localizedDescription)"
        }
        isLoadingParks = false
    }

    @MainActor
    func loadRidesAndLocations() async {
        guard let park = selectedPark else { return }
        isLoading = true
        errorMessage = nil

        async let liveTask = ParkAPIService.shared.fetchLiveData(for: park.id)
        async let locTask: [AttractionEntity] = {
            if attractionLocations[park.id] != nil {
                return []
            }
            return (try? await ParkAPIService.shared.fetchAttractionChildren(parkId: park.id)) ?? []
        }()

        do {
            let (liveEntries, attractions) = try await (liveTask, locTask)

            for attraction in attractions {
                if let coord = attraction.coordinate {
                    attractionLocations[attraction.id] = coord
                }
            }

            let newRides = liveEntries
                .filter { $0.entityType == "ATTRACTION" }
                .map { entry in
                    DisplayRide(live: entry, location: attractionLocations[entry.id])
                }
            rides = newRides
            lastRefreshed = .now
            currentParkId = park.id
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func refresh() async {
        await loadRidesAndLocations()
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled {
                    await MainActor.run { Task { await self.loadRidesAndLocations() } }
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

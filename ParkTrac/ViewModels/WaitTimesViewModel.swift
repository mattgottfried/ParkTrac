import Foundation
import CoreLocation
import Observation

@Observable
final class WaitTimesViewModel {

    // MARK: - Blocked attractions (never have standby queues)
    private let blockedAttractions: Set<String> = [
        // Magic Kingdom
        "A Pirate's Adventure ~ Treasures of the Seven Seas",
        "Casey Jr. Splash 'N' Soak Station",
        "Cinderella Castle",
        "Main Street Vehicles",
        // EPCOT
        "Advanced Training Lab",
        "American Heritage Gallery",
        "Awesome Planet",
        "Bijutsu-kan Gallery",
        "Bruce's Shark World",
        "Disney and Pixar Short Film Festival",
        "Gallery of Arts and History",
        "House of the Whispering Willows",
        "ImageWorks - The \"What If\" Labs",
        "Impressions de France",
        "Journey of Water, Inspired by Moana",
        "Kidcot Fun Stops",
        "Mexico Folk Art Gallery",
        "Palais du Cinéma",
        "Project Tomorrow: Inventing the Wonders of the Future",
        "SeaBase Aquarium",
        "Stave Church Gallery",
        "The American Adventure",
        // Hollywood Studios
        "Walt Disney Presents",
        // Animal Kingdom
        "Discovery Island Trails",
        "The Oasis Exhibits",
        "Tree of Life",
        "Wilderness Explorers",
        "Affection Section",
        "Animal Care at Conservation Station",
        "Wildlife Express Train",
        // Islands of Adventure
        "Camp Jurassic™",
        "If I Ran The Zoo™",
        "Jurassic Park Discovery Center™",
        "Me Ship, The Olive®",
        "Pteranodon Flyers",
    ]

    // MARK: - State

    var selectedGroup: ParkGroup = .disney {
        didSet {
            filterPark = nil
            Task { await loadAllParksInGroup() }
        }
    }

    /// Which park chip is selected for list filtering (nil = all parks)
    var filterPark: ParkEntity? = nil

    var parksByGroup: [ParkGroup: [ParkEntity]] = [:]
    var currentParks: [ParkEntity] { parksByGroup[selectedGroup] ?? [] }

    private var attractionLocations: [String: CLLocationCoordinate2D] = [:]

    /// Rides keyed by park ID — all parks in the current group
    private var ridesByPark: [String: [DisplayRide]] = [:]

    /// Shows keyed by park ID
    private var showsByPark: [String: [DisplayShow]] = [:]

    /// Schedule keyed by park ID
    var schedulesByPark: [String: [ParkScheduleDay]] = [:]

    /// Sort preference — set from AppState/Settings
    var sortAlphabetical: Bool = false

    /// Flat merge of rides for the **current group only** (prevents cross-resort bleed)
    var allRides: [DisplayRide] {
        let currentParkIds = Set(currentParks.map(\.id))
        return Array(ridesByPark.filter { currentParkIds.contains($0.key) }.values.joined())
    }

    /// Shows for the currently filtered park (or all parks if no filter)
    var currentShows: [DisplayShow] {
        let currentParkIds = Set(currentParks.map(\.id))
        let all = Array(showsByPark.filter { currentParkIds.contains($0.key) }.values.joined())
        let filtered = filterPark == nil ? all : all.filter { $0.parkId == filterPark?.id }
        return filtered
            .filter { !blockedAttractions.contains($0.name) }
            .filter { $0.status != "CLOSED" }
            .sorted { ($0.nextShowtime ?? .distantFuture) < ($1.nextShowtime ?? .distantFuture) }
    }

    /// Today's schedule for the currently selected park (operating hours only)
    func todaySchedule(for park: ParkEntity) -> [ParkScheduleDay] {
        guard let days = schedulesByPark[park.id] else { return [] }
        let todayStr = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: .now)).prefix(10)
        return days.filter { $0.date.hasPrefix(todayStr) }
    }

    var isLoading = false
    var isLoadingParks = false
    var errorMessage: String?
    var searchText = ""
    var lastRefreshed: Date?

    private var refreshTask: Task<Void, Never>?

    // MARK: - Computed

    // MARK: - Crowd Level (live, no history needed)

    var currentCrowdLevel: CrowdLevel? {
        let waits = filteredRides.filter { $0.isOperating }.compactMap(\.waitMinutes)
        guard !waits.isEmpty else { return nil }
        let avg = Double(waits.reduce(0, +)) / Double(waits.count)
        return CrowdLevel.from(averageWait: avg)
    }

    var currentAverageWait: Double? {
        let waits = filteredRides.filter { $0.isOperating }.compactMap(\.waitMinutes)
        guard !waits.isEmpty else { return nil }
        return Double(waits.reduce(0, +)) / Double(waits.count)
    }

    // MARK: - Filtered rides

    var filteredRides: [DisplayRide] {
        allRides
            .filter { !blockedAttractions.contains($0.name) }
            .filter { $0.status != "CLOSED" && $0.status != "REFURBISHMENT" }
            .filter { filterPark == nil || $0.parkId == filterPark?.id }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { lhs, rhs in
                if sortAlphabetical {
                    return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                }
                // Default: operating first, then by descending wait time
                if lhs.isOperating != rhs.isOperating { return lhs.isOperating }
                return (lhs.waitMinutes ?? -1) > (rhs.waitMinutes ?? -1)
            }
    }

    /// Alias for allRides — used by views
    var rides: [DisplayRide] { allRides }

    /// Map annotations: operating rides only (no closed/blocked markers on map)
    var ridesWithLocation: [DisplayRide] {
        allRides
            .filter { $0.isOperating }
            .filter { !blockedAttractions.contains($0.name) }
            .filter { $0.coordinate != nil }
    }

    // MARK: - Loading

    @MainActor
    func loadAllParks() async {
        await withTaskGroup(of: Void.self) { group in
            for parkGroup in ParkGroup.allCases {
                group.addTask { await self.loadParksIfNeeded(for: parkGroup) }
            }
        }
        await loadAllParksInGroup()
    }

    @MainActor
    func loadParksIfNeeded(for group: ParkGroup) async {
        guard parksByGroup[group] == nil else { return }
        isLoadingParks = true
        do {
            let parks = try await ParkAPIService.shared.fetchDestinationChildren(destinationId: group.destinationId)
            parksByGroup[group] = parks
        } catch {
            errorMessage = "Could not load parks: \(error.localizedDescription)"
        }
        isLoadingParks = false
    }

    /// Loads live ride data for every park in the current group in parallel.
    @MainActor
    func loadAllParksInGroup() async {
        guard let parks = parksByGroup[selectedGroup], !parks.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        await withTaskGroup(of: Void.self) { group in
            for park in parks {
                group.addTask { await self.loadRidesForPark(park) }
            }
        }
        lastRefreshed = .now
        isLoading = false
    }

    @MainActor
    private func loadRidesForPark(_ park: ParkEntity) async {
        // Fetch locations once per park
        if attractionLocations[park.id] == nil {
            let attractions = (try? await ParkAPIService.shared.fetchAttractionChildren(parkId: park.id)) ?? []
            for attraction in attractions {
                if let coord = attraction.coordinate {
                    attractionLocations[attraction.id] = coord
                }
            }
        }

        guard let liveEntries = try? await ParkAPIService.shared.fetchLiveData(for: park.id) else { return }

        let newRides = liveEntries
            .filter { $0.entityType == "ATTRACTION" }
            .map { entry in
                DisplayRide(live: entry, parkId: park.id, location: attractionLocations[entry.id])
            }
        ridesByPark[park.id] = newRides

        // Collect show entities
        let newShows = liveEntries
            .filter { $0.entityType == "SHOW" || $0.entityType == "ENTERTAINMENT" }
            .map { DisplayShow(live: $0, parkId: park.id) }
        showsByPark[park.id] = newShows

        // Fetch schedule once per day (only if stale or missing)
        let scheduleKey = park.id
        if schedulesByPark[scheduleKey] == nil {
            if let schedule = try? await ParkAPIService.shared.fetchSchedule(parkId: park.id) {
                schedulesByPark[scheduleKey] = schedule
            }
        }
    }

    @MainActor
    func refresh() async {
        await loadAllParksInGroup()
    }

    @MainActor
    func loadRides() async {
        await loadAllParksInGroup()
    }

    @MainActor
    func retry() async {
        errorMessage = nil
        if parksByGroup[selectedGroup] == nil {
            await loadAllParks()
        } else {
            await loadAllParksInGroup()
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled {
                    await MainActor.run { Task { await self.loadAllParksInGroup() } }
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit { stopAutoRefresh() }
}

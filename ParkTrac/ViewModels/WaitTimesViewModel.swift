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
            rebuildAllRides()
            Task { await loadAllParksInGroup() }
        }
    }

    /// Which park chip is selected for list filtering (nil = all parks)
    var filterPark: ParkEntity? = nil

    var parksByGroup: [ParkGroup: [ParkEntity]] = [:]
    var currentParks: [ParkEntity] { parksByGroup[selectedGroup] ?? [] }

    private var attractionLocations: [String: CLLocationCoordinate2D] = [:]

    // MARK: - Ride catalog
    // Persisted list of every ride per park so the list never empties when a
    // park closes. Refreshed once per calendar day (first refresh of the
    // morning) to pick up newly added rides.

    private struct CatalogRide: Codable {
        let id: String
        let name: String
        let latitude: Double?
        let longitude: Double?
    }

    private var catalogsByPark: [String: [CatalogRide]] = [:]

    private var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // Main-actor isolated: concurrent park loads (several at once when switching resorts)
    // used to write catalogsByPark from background threads, corrupting the dictionary → crash.
    @MainActor
    private func loadCatalog(for parkId: String) -> [CatalogRide]? {
        if let cached = catalogsByPark[parkId] { return cached }
        guard let data = UserDefaults.standard.data(forKey: "rideCatalog_\(parkId)"),
              let catalog = try? JSONDecoder().decode([CatalogRide].self, from: data) else { return nil }
        catalogsByPark[parkId] = catalog
        return catalog
    }

    @MainActor
    private func refreshCatalogIfNeeded(for park: ParkEntity) async {
        let dayKey = "rideCatalogDay_\(park.id)"
        if UserDefaults.standard.string(forKey: dayKey) == todayKey,
           loadCatalog(for: park.id) != nil {
            return
        }
        // Keep the stale catalog when the fetch fails — better old rides than none
        guard let attractions = try? await ParkAPIService.shared.fetchAttractionChildren(parkId: park.id),
              !attractions.isEmpty else { return }
        let catalog = attractions
            .filter { $0.entityType == "ATTRACTION" }
            .map { CatalogRide(id: $0.id, name: $0.name,
                               // validated (both present, not a 0,0 placeholder)
                               latitude: $0.coordinate?.latitude,
                               longitude: $0.coordinate?.longitude) }
        catalogsByPark[park.id] = catalog
        if let data = try? JSONEncoder().encode(catalog) {
            UserDefaults.standard.set(data, forKey: "rideCatalog_\(park.id)")
            UserDefaults.standard.set(todayKey, forKey: dayKey)
        }
    }

    /// Rides keyed by park ID — all parks in the current group
    private var ridesByPark: [String: [DisplayRide]] = [:]

    /// Shows keyed by park ID
    private var showsByPark: [String: [DisplayShow]] = [:]

    /// Schedule keyed by park ID
    var schedulesByPark: [String: [ParkScheduleDay]] = [:]

    /// Sort preference — set from ParkMapView (@AppStorage "rideSort", mirrored with Settings' A–Z toggle)
    var rideSort: RideSort = .longestWait

    /// Flat merge of rides for the **current group only** (prevents cross-resort bleed).
    /// Stored (not computed) so map annotations, list, and crowd stats don't re-join
    /// ridesByPark on every body evaluation — rebuilt once per refresh.
    private(set) var allRides: [DisplayRide] = []

    private func rebuildAllRides() {
        let currentParkIds = Set(currentParks.map(\.id))
        allRides = Array(ridesByPark.filter { currentParkIds.contains($0.key) }.values.joined())
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

    /// Every show at the current resort, ignoring the park filter (live plan)
    var allShowsForPlanning: [DisplayShow] {
        let currentParkIds = Set(currentParks.map(\.id))
        return Array(showsByPark.filter { currentParkIds.contains($0.key) }.values.joined())
    }

    /// Today's schedule for the currently selected park (operating hours only)
    func todaySchedule(for park: ParkEntity) -> [ParkScheduleDay] {
        schedule(for: park, on: .now)
    }

    /// A day's schedule entries (the API publishes about a month ahead). Pass a time inside
    /// the day — `FutureDay.noon` — so the park-time-zone day matches the calendar day.
    func schedule(for park: ParkEntity, on date: Date) -> [ParkScheduleDay] {
        guard let days = schedulesByPark[park.id] else { return [] }
        // The day in the park's time zone — ISO8601DateFormatter defaults to UTC, which
        // picked yesterday's schedule for parks east of UTC (Japan) before 9 AM local.
        let group = parksByGroup.first { $0.value.contains { $0.id == park.id } }?.key ?? selectedGroup
        let dayStr = Self.dayString(date, in: group.timeZone)
        return days.filter { $0.date.hasPrefix(dayStr) }
    }

    /// Today's schedule entries for every loaded park at a resort (parking reminder uses the latest close)
    func todaySchedule(forResort group: ParkGroup) -> [ParkScheduleDay] {
        (parksByGroup[group] ?? []).flatMap { todaySchedule(for: $0) }
    }

    static func dayString(_ date: Date, in timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    var isLoading = false
    var isLoadingParks = false
    var errorMessage: String?
    var searchText = ""
    var lastRefreshed: Date?

    /// Rising/falling arrow per ride vs. its wait on the previous refresh.
    private(set) var waitTrends: [String: WaitTrend] = [:]

    /// Set when a park has no live data at all this session (no signal). The ride list still
    /// shows the roster, but with no wait times or status — showing a stale number would be
    /// misleading, so it isn't cached or reused across launches.
    var isOffline = false

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
            .filter { filterPark == nil || $0.parkId == filterPark?.id }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { lhs, rhs in
                if rideSort == .name {
                    return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                }
                // Operating (by wait) → temporarily down → closed (A–Z)
                let lRank = statusRank(lhs), rRank = statusRank(rhs)
                if lRank != rRank { return lRank < rRank }
                if lRank == 0 {
                    let l = lhs.waitMinutes ?? -1, r = rhs.waitMinutes ?? -1
                    if l != r { return rideSort == .shortestWait ? l < r : l > r }
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
    }

    private func statusRank(_ ride: DisplayRide) -> Int {
        if ride.isOperating { return 0 }
        if ride.status == "DOWN" { return 1 }
        return 2  // CLOSED / REFURBISHMENT / unknown
    }

    /// Alias for allRides — used by views
    var rides: [DisplayRide] { allRides }

    /// Every ride at a park (minus non-ride attractions like castles/trails), for Park Bingo.
    /// Pass nil for the whole resort's roster across every park in the current group.
    func rideRoster(for park: ParkEntity? = nil) -> [String] {
        allRides
            .filter { park == nil || $0.parkId == park?.id }
            .filter { !blockedAttractions.contains($0.name) }
            .map(\.name)
    }

    /// Map annotations: operating rides only (no closed/blocked markers on map)
    var ridesWithLocation: [DisplayRide] {
        allRides
            .filter { $0.isOperating || $0.status == "DOWN" }
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
        // An empty list counts as "not loaded" so a failed lookup retries next time
        guard parksByGroup[group]?.isEmpty ?? true else { return }
        isLoadingParks = true
        do {
            let parks = try await ParkAPIService.shared.fetchParks(for: group)
            parksByGroup[group] = parks
        } catch {
            errorMessage = "Could not load parks: \(error.localizedDescription)"
        }
        isLoadingParks = false
    }

    /// Loads live ride data for every park in the current group in parallel.
    @MainActor
    func loadAllParksInGroup() async {
        // Parks are fetched at launch; if that failed for this resort (e.g. Japan lookup),
        // retry now instead of silently showing an empty list.
        if parksByGroup[selectedGroup]?.isEmpty ?? true {
            await loadParksIfNeeded(for: selectedGroup)
        }
        guard let parks = parksByGroup[selectedGroup], !parks.isEmpty else {
            if errorMessage == nil {
                errorMessage = "Couldn't load \(selectedGroup.rawValue) parks. Check your connection and try again."
            }
            return
        }
        isLoading = true
        errorMessage = nil
        isOffline = false
        let previousWaits = Dictionary(uniqueKeysWithValues: allRides.compactMap { ride in
            ride.waitMinutes.map { (ride.id, $0) }
        })
        var successCount = 0
        await withTaskGroup(of: Bool.self) { group in
            for park in parks {
                group.addTask { await self.loadRidesForPark(park) }
            }
            for await succeeded in group where succeeded {
                successCount += 1
            }
        }
        // Keep stale data visible on failure; only surface an error when nothing loaded.
        // A cancelled refresh isn't a connection problem, and the offline banner (below)
        // already explains the no-signal case — no need for the red error too.
        if successCount == 0 && !Task.isCancelled && !isOffline {
            errorMessage = "Couldn't refresh wait times. Check your connection."
        }
        rebuildAllRides()
        if successCount > 0 {
            waitTrends = Dictionary(uniqueKeysWithValues: allRides.compactMap { ride -> (String, WaitTrend)? in
                guard let wait = ride.waitMinutes,
                      let trend = WaitTrend.compute(previous: previousWaits[ride.id], current: wait) else { return nil }
                return (ride.id, trend)
            })
        }
        if successCount > 0 {
            LightningLaneWatchService.shared.check(rides: allRides)
            ReopenWatchService.shared.check(rides: allRides)
            InstantAlertsService.shared.refreshIfStale()
        }
        // Only advance on real data — a stale timestamp drives the "out of date" warning
        // and keeps the recorder from re-recording cached waits as new snapshots.
        if successCount > 0 { lastRefreshed = .now }
        isLoading = false
    }

    @MainActor
    private func loadRidesForPark(_ park: ParkEntity) async -> Bool {
        await refreshCatalogIfNeeded(for: park)
        let catalog = loadCatalog(for: park.id) ?? []
        for entry in catalog {
            if let lat = entry.latitude, let lon = entry.longitude {
                attractionLocations[entry.id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }

        guard let liveEntries = try? await ParkAPIService.shared.fetchLiveData(for: park.id) else {
            // No live data at all (no signal / park closed overnight on some endpoints): show
            // the roster with no wait/status rather than either an empty list or a stale,
            // possibly-wrong number.
            if ridesByPark[park.id] == nil && !catalog.isEmpty {
                ridesByPark[park.id] = catalog.map {
                    DisplayRide(catalogId: $0.id, name: $0.name, parkId: park.id,
                                location: attractionLocations[$0.id], status: "UNKNOWN")
                }
                isOffline = true
            }
            return false
        }

        // Catalog is the roster; live data fills in wait/status. Rides missing
        // from live data show as Closed instead of disappearing.
        let liveAttractions = liveEntries.filter { $0.entityType == "ATTRACTION" }
        let liveById = Dictionary(liveAttractions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let catalogIds = Set(catalog.map(\.id))

        var newRides: [DisplayRide] = catalog.map { entry in
            if let live = liveById[entry.id] {
                return DisplayRide(live: live, parkId: park.id, location: attractionLocations[entry.id])
            }
            return DisplayRide(catalogId: entry.id, name: entry.name, parkId: park.id,
                               location: attractionLocations[entry.id])
        }
        // Rides that appeared in live data before the daily catalog caught up
        newRides += liveAttractions
            .filter { !catalogIds.contains($0.id) }
            .map { DisplayRide(live: $0, parkId: park.id, location: attractionLocations[$0.id]) }

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
        return true
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
                    await self.loadAllParksInGroup()
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

// MARK: - Closing soon

/// A "rides start closing soon" heads-up for the ride list, separate from `ParkingReminder`'s
/// leave-by push notification — this is just an in-app banner while a single park is in focus.
enum ClosingSoon {
    static let leadMinutes = 45

    /// Minutes until the latest regular (non-ticketed) close today; nil once it's passed,
    /// too far off, or the schedule hasn't loaded.
    static func minutesUntilClose(schedule: [ParkScheduleDay], now: Date = .now) -> Int? {
        let closings = schedule.filter { !$0.isTicketedEvent }.compactMap(\.closingDate)
        guard let closing = closings.max(), closing > now else { return nil }
        let minutes = Int(closing.timeIntervalSince(now) / 60)
        return minutes <= leadMinutes ? minutes : nil
    }
}

// MARK: - Ride Sort

enum RideSort: String, CaseIterable, Identifiable {
    case longestWait, shortestWait, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .longestWait:  return "Longest Wait"
        case .shortestWait: return "Shortest Wait"
        case .name:         return "Name (A–Z)"
        }
    }
}

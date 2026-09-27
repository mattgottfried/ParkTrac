import Foundation
import CoreLocation
import SwiftData

// MARK: - Interests

/// Genie-style interests: fill open time with rides the party likes.
enum Interest: String, CaseIterable, Codable, Identifiable {
    case thrill, coasters, gentle, darkRides, water, simulators, shows

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thrill:     return "Thrill Rides"
        case .coasters:   return "Coasters"
        case .gentle:     return "Slow & Gentle"
        case .darkRides:  return "Dark Rides"
        case .water:      return "Water Rides"
        case .simulators: return "Simulators"
        case .shows:      return "Shows"
        }
    }

    var systemImage: String {
        switch self {
        case .thrill:     return "flame.fill"
        case .coasters:   return "bolt.fill"
        case .gentle:     return "leaf.fill"
        case .darkRides:  return "moon.fill"
        case .water:      return "drop.fill"
        case .simulators: return "gamecontroller.fill"
        case .shows:      return "theatermasks.fill"
        }
    }

    /// Does a ride fit this interest? (Shows are matched separately.)
    func matches(_ info: RideInfo?) -> Bool {
        guard let info else { return false }
        switch self {
        case .thrill:     return info.thrill == .thrilling || info.thrill == .extreme
        case .coasters:   return info.type == .coaster
        case .gentle:     return info.thrill == .family
        case .darkRides:  return info.type == .darkRide
        case .water:      return info.type == .water
        case .simulators: return info.type == .simulator
        case .shows:      return info.type == .showOrLive
        }
    }

    /// Loose words Apple Intelligence may return → interests
    static func from(_ words: [String]) -> [Interest] {
        var result: [Interest] = []
        for word in words.map({ $0.lowercased() }) {
            let match: Interest?
            if word.contains("coaster") { match = .coasters }
            else if word.contains("thrill") || word.contains("intense") { match = .thrill }
            else if word.contains("gentle") || word.contains("slow") || word.contains("family") || word.contains("calm") { match = .gentle }
            else if word.contains("dark") { match = .darkRides }
            else if word.contains("water") || word.contains("wet") { match = .water }
            else if word.contains("simulat") { match = .simulators }
            else if word.contains("show") || word.contains("parade") { match = .shows }
            else { match = nil }
            if let match, !result.contains(match) { result.append(match) }
        }
        return result
    }
}

// MARK: - Today's plan (what the guest chose)

/// The plan the guest started from the Smart Planner. Synced through iCloud so both phones
/// follow the same day; what's live (times, next stop) is recomputed on each phone.
struct DayItinerary: Codable, Equatable {
    struct Pick: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var parkId: String
    }

    struct Extra: Codable, Equatable {
        var title: String
        var kind: String       // "dining" | "break"
        var start: Date
        var minutes: Int
    }

    var day: Date
    var resortRaw: String
    var rides: [Pick]
    var shows: [Pick]
    var interests: [Interest]
    var notes: String
    /// Ride ids in Apple Intelligence's order (empty = ThrillTrack orders them)
    var aiOrder: [String]
    var aiSummary: String?
    /// Meals / breaks Apple Intelligence read from the notes
    var extras: [Extra]
    var doneIds: [String] = []
    var skippedIds: [String] = []

    var resort: ParkGroup { ParkGroup(rawValue: resortRaw) ?? .disney }

    func isToday(now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }

    /// Picked rides still to do, in plan order (Apple Intelligence's when it gave one)
    var remainingRides: [Pick] {
        let open = rides.filter { !doneIds.contains($0.id) && !skippedIds.contains($0.id) }
        guard !aiOrder.isEmpty else { return open }
        let rank = Dictionary(aiOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return open.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }
}

// MARK: - Tip Board (pure)

enum TipBoard {
    struct Row: Equatable, Identifiable {
        let id: String
        let name: String
        let waitNow: Int?
        let isOperating: Bool
        /// Usual wait at this time (GoodTimeToRide)
        let usualNow: Int?
        /// Lowest expected wait for the rest of today, and when
        let bestHour: Int?
        let bestWait: Int?
        let isMustDo: Bool

        /// "Good time now" when the wait is well below usual, or it's at today's low
        var isGoodNow: Bool {
            guard isOperating, let waitNow else { return false }
            if let usualNow, GoodTimeToRide.deal(rideId: id, wait: waitNow, isOperating: true,
                                                   usual: .init(minutes: usualNow, basis: .usualAtThisTime)) != nil {
                return true
            }
            if let bestWait { return waitNow <= bestWait + 5 }
            return false
        }
    }

    /// Best remaining hour today from a ride's hourly profile (current hour onward)
    static func best(profile: [Int: Int], fromHour: Int, untilHour: Int) -> (hour: Int, wait: Int)? {
        guard fromHour <= untilHour else { return nil }
        return (fromHour...untilHour)
            .compactMap { h -> (hour: Int, wait: Int)? in profile[h].map { (hour: h, wait: $0) } }
            .min { $0.wait < $1.wait || ($0.wait == $1.wait && $0.hour < $1.hour) }
    }
}

// MARK: - Interest suggestions (pure)

enum InterestSuggestions {
    struct Candidate: Equatable {
        let id: String
        let name: String
        let wait: Int
        let walk: Int
        let info: RideInfo?
    }

    /// Rides that fit the party's interests, aren't already planned or done, and are short right now.
    static func pick(_ candidates: [Candidate], interests: [Interest], excluding: Set<String>,
                     maxWait: Int = 30, limit: Int = 3) -> [Candidate] {
        guard !interests.isEmpty else { return [] }
        return candidates
            .filter { c in !excluding.contains(c.id) && c.wait <= maxWait && interests.contains { $0.matches(c.info) } }
            .sorted { ($0.wait + $0.walk) < ($1.wait + $1.walk) }
            .prefix(limit)
            .map { $0 }
    }
}

extension RideInfo: Equatable {
    static func == (a: RideInfo, b: RideInfo) -> Bool {
        a.heightInches == b.heightInches && a.heightCm == b.heightCm && a.maxHeightCm == b.maxHeightCm
            && a.thrill == b.thrill && a.type == b.type && a.lightningLane == b.lightningLane
    }
}

// MARK: - Plan inputs (shared by the Smart Planner and the live plan)

enum PlanInputs {
    /// Each ride's own expected wait by hour: this phone's history, else live wait × park curve.
    /// This phone's recorded waits for these rides over the last `days` days
    @MainActor
    static func history(for ids: Set<String>, days: Int, context: ModelContext) -> [String: [(date: Date, wait: Int)]] {
        let since = Date.now.addingTimeInterval(-Double(days) * 86_400)
        let records = ((try? context.fetch(FetchDescriptor<WaitTimeRecord>(
            predicate: #Predicate { $0.recordedAt >= since }))) ?? []).filter { ids.contains($0.rideId) }
        var history: [String: [(date: Date, wait: Int)]] = [:]
        for r in records {
            if let w = r.waitMinutes { history[r.rideId, default: []].append((date: r.recordedAt, wait: w)) }
        }
        return history
    }

    @MainActor
    static func planRides(_ rides: [DisplayRide], parks: [ParkEntity], fallbackParkName: String,
                          context: ModelContext) -> [PlanRide] {
        let history = history(for: Set(rides.map(\.id)), days: RideProfile.historyDays, context: context)
        return rides.map { ride -> PlanRide in
            let park = parks.first { $0.id == ride.parkId }?.name ?? fallbackParkName
            var curve: [Int: Double] = [:]
            for hour in RideProfile.dayHours {
                curve[hour] = CommunityBaselineService.shared.adjustedHourlyAvg(for: park, hour: hour)
            }
            return PlanRide(id: ride.id, name: ride.name, parkName: park,
                            latitude: ride.coordinate?.latitude, longitude: ride.coordinate?.longitude,
                            waitByHour: RideProfile.waitsByHour(samples: history[ride.id] ?? [],
                                                                currentWait: ride.waitMinutes, parkCurve: curve,
                                                                community: CommunityHistoryService.shared.waitsByHour(
                                                                    rideId: ride.id, parkId: ride.parkId)))
        }
    }

    /// Today's dining reservations at the resort from `after` on
    @MainActor
    static func dining(resort: ParkGroup, after: Date, context: ModelContext, parkName: String) -> [FixedEvent] {
        let all = (try? context.fetch(FetchDescriptor<DiningReservation>())) ?? []
        return all
            .filter { $0.resort == resort.rawValue && !$0.isCompleted && Calendar.current.isDateInToday($0.date)
                && $0.date.addingTimeInterval(75 * 60) > after }
            .map { FixedEvent(title: "Dining: \($0.restaurantName)", kind: "dining", start: $0.date, minutes: 75,
                              parkName: parkName) }
    }
}

// MARK: - Service

/// Today's live plan: re-planned from now after every wait-time refresh.
@Observable
final class ItineraryService {
    static let shared = ItineraryService()

    private static let storageKey = "dayItinerary"
    private let icloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// The started plan (any day — check `active(for:)`)
    private(set) var itinerary: DayItinerary?
    /// Current timed plan from now on
    private(set) var live: DayPlan?
    private(set) var liveUpdatedAt: Date?
    /// Rides that fit the party's interests and are short now
    private(set) var suggestions: [InterestSuggestions.Candidate] = []
    /// Where the guest was at the last re-plan (cards re-plan without a location service)
    private(set) var lastLocation: CLLocationCoordinate2D?

    private init() {
        itinerary = Self.decode(icloud.data(forKey: Self.storageKey) ?? defaults.data(forKey: Self.storageKey))
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // The other phone started a plan or ticked something off
            self.itinerary = Self.decode(self.icloud.data(forKey: Self.storageKey))
        }
    }

    /// Today's plan for this resort, if one is running
    func active(for resort: ParkGroup) -> DayItinerary? {
        guard let itinerary, itinerary.isToday(), itinerary.resort == resort else { return nil }
        return itinerary
    }

    /// The next thing to do (ride or set-time event) in the live plan
    var nextStop: PlannedStop? { live?.stops.first }

    func start(_ plan: DayItinerary) {
        itinerary = plan
        live = nil
        persist()
    }

    func end() {
        itinerary = nil
        live = nil
        suggestions = []
        persist()
    }

    func markDone(_ rideId: String) {
        guard var it = itinerary, !it.doneIds.contains(rideId) else { return }
        it.doneIds.append(rideId)
        itinerary = it
        live?.stops.removeAll { $0.rideId == rideId }
        persist()
    }

    func skip(_ rideId: String) {
        guard var it = itinerary, !it.skippedIds.contains(rideId) else { return }
        it.skippedIds.append(rideId)
        itinerary = it
        live?.stops.removeAll { $0.rideId == rideId }
        persist()
    }

    func add(_ pick: DayItinerary.Pick) {
        guard var it = itinerary, !it.rides.contains(where: { $0.id == pick.id }) else { return }
        it.rides.append(pick)
        it.skippedIds.removeAll { $0 == pick.id }
        itinerary = it
        persist()
    }

    /// Re-plan from now. Called after every foreground refresh (ParkMapView) and when the plan changes.
    @MainActor
    func replan(viewModel: WaitTimesViewModel, resort: ParkGroup, location currentLocation: CLLocationCoordinate2D?,
                context: ModelContext) {
        if let currentLocation { lastLocation = currentLocation }
        let location = currentLocation ?? lastLocation
        guard var it = active(for: resort) else {
            live = nil
            suggestions = []
            return
        }

        // Anything logged with "Rode It" today counts as done
        let today = Calendar.current.startOfDay(for: .now)
        let logs = (try? context.fetch(FetchDescriptor<RideLog>(predicate: #Predicate { $0.riddenAt >= today }))) ?? []
        let ridden = Set(logs.map(\.rideId))
        let newlyDone = it.rides.map(\.id).filter { ridden.contains($0) && !it.doneIds.contains($0) }
        if !newlyDone.isEmpty {
            it.doneIds += newlyDone
            itinerary = it
            persist()
        }

        let now = Date.now
        let parks = viewModel.parksByGroup[resort] ?? []
        let fallbackPark = parks.first?.name ?? ""
        let rideById = Dictionary(viewModel.allRides.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remaining = it.remainingRides.compactMap { rideById[$0.id] }.filter(\.isOperating)
        let planRides = PlanInputs.planRides(remaining, parks: parks, fallbackParkName: fallbackPark, context: context)

        // Set times: picked shows' next showing, dining, meals/breaks from the notes
        let showIds = Set(it.shows.map(\.id))
        var fixed = viewModel.allShowsForPlanning
            .filter { showIds.contains($0.id) }
            .compactMap { show -> FixedEvent? in
                show.nextShowtime.map { FixedEvent(title: show.name, kind: "show", start: $0, minutes: 25,
                                                   parkName: fallbackPark) }
            }
        fixed += PlanInputs.dining(resort: resort, after: now, context: context, parkName: fallbackPark)
        fixed += it.extras.map { FixedEvent(title: $0.title, kind: $0.kind, start: $0.start, minutes: $0.minutes,
                                            parkName: fallbackPark) }

        let close = parks.flatMap { viewModel.todaySchedule(for: $0) }
            .filter { !$0.isTicketedEvent }.compactMap(\.closingDate).max()

        live = it.aiOrder.isEmpty
            ? DayPlanBuilder.build(rides: planRides, fixed: fixed, start: now, end: close, from: location)
            : DayPlanBuilder.build(ordered: planRides, fixed: fixed, start: now, end: close, from: location)
        liveUpdatedAt = now

        // Interest suggestions to fill open time
        let planned = Set(it.rides.map(\.id)).union(it.doneIds)
        let candidates = viewModel.allRides.compactMap { ride -> InterestSuggestions.Candidate? in
            guard ride.isOperating, let wait = ride.waitMinutes else { return nil }
            let walk = DayPlanBuilder.walkMinutes(from: location, to: ride.coordinate)
            return .init(id: ride.id, name: ride.name, wait: wait, walk: location == nil ? 0 : walk,
                         info: RideMetadata.info(for: ride.name, resort: resort))
        }
        suggestions = InterestSuggestions.pick(candidates, interests: it.interests, excluding: planned)
    }

    private func persist() {
        if let itinerary, let data = try? JSONEncoder().encode(itinerary) {
            icloud.set(data, forKey: Self.storageKey)
            defaults.set(data, forKey: Self.storageKey)
        } else {
            icloud.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    static func decode(_ data: Data?) -> DayItinerary? {
        data.flatMap { try? JSONDecoder().decode(DayItinerary.self, from: $0) }
    }
}

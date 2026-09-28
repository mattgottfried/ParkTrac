import Foundation
import CoreLocation

// MARK: - Inputs

/// A ride the planner may schedule, with its expected posted wait by hour of day.
struct PlanRide: Equatable {
    let id: String
    let name: String
    let parkName: String
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// Hour of day (0–23) → expected posted wait in minutes (`RideProfile.waitsByHour`)
    let waitByHour: [Int: Int]
    /// Ride + exit time
    var rideMinutes: Int = 10
    /// Mostly indoors (`RideMetadata.isIndoor`) — preferred during rain
    var isIndoor: Bool = false

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Expected wait at `date`: that hour's estimate, else the nearest hour we have, else 30.
    func wait(at date: Date, calendar: Calendar = .current) -> Int {
        let hour = calendar.component(.hour, from: date)
        if let w = waitByHour[hour] { return w }
        let nearest = waitByHour.keys.min { abs($0 - hour) < abs($1 - hour) }
        return nearest.flatMap { waitByHour[$0] } ?? 30
    }

    /// Lowest expected wait from `date` until `end` (by hour)
    func bestWait(from date: Date, until end: Date?, calendar: Calendar = .current) -> Int {
        let startHour = calendar.component(.hour, from: date)
        let endHour = end.map { calendar.component(.hour, from: $0) } ?? 23
        let hours = startHour <= endHour ? Array(startHour...endHour) : [startHour]
        return hours.map { hour -> Int in
            waitByHour[hour] ?? wait(at: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date,
                                     calendar: calendar)
        }.min() ?? wait(at: date, calendar: calendar)
    }
}

/// Something at a set time: a show, a dining reservation, a break the guest asked for.
struct FixedEvent: Equatable {
    let title: String
    /// "show" | "dining" | "break"
    let kind: String
    let start: Date
    let minutes: Int
    var parkName: String = ""
}

// MARK: - Output

struct PlannedStop: Equatable {
    let title: String
    let kind: String      // "ride" | "show" | "dining" | "break"
    let rideId: String?
    let parkName: String
    let start: Date
    let walkMinutes: Int
    let waitMinutes: Int
    let totalMinutes: Int

    var end: Date { start.addingTimeInterval(Double(totalMinutes) * 60) }
}

struct DayPlan: Equatable {
    var stops: [PlannedStop]
    /// Rides that didn't fit before the end of the day
    var unscheduled: [String]

    /// Total standing-in-line time — shows/dining/breaks carry no wait, only ride stops do.
    var totalWaitMinutes: Int { stops.filter { $0.kind == "ride" }.reduce(0) { $0 + $1.waitMinutes } }
}

// MARK: - Per-ride wait profile

enum RideProfile {
    /// Personal history needs this many samples in an hour to be trusted
    static let minSamplesPerHour = 3
    static let historyDays = 30
    static let dayHours = 7...23

    /// Expected posted wait for each hour of the day, per ride:
    /// 1. this phone's recorded median for that hour (last 30 days),
    /// 2. else the server's community history for this ride on this weekday (`CommunityHistoryService`),
    /// 3. else the live wait scaled by the park's typical daily curve,
    /// and the current hour is always the live wait.
    static func waitsByHour(samples: [(date: Date, wait: Int)], currentWait: Int?, now: Date = .now,
                            parkCurve: [Int: Double], community: [Int: Int] = [:],
                            pinCurrentHour: Bool = true,
                            calendar: Calendar = .current) -> [Int: Int] {
        let cutoff = now.addingTimeInterval(-Double(historyDays) * 86_400)
        var byHour: [Int: [Int]] = [:]
        for s in samples where s.date >= cutoff {
            byHour[calendar.component(.hour, from: s.date), default: []].append(s.wait)
        }
        var result: [Int: Int] = [:]
        for (hour, waits) in byHour where waits.count >= minSamplesPerHour {
            if let m = GoodTimeToRide.median(waits) { result[hour] = m }
        }

        for (hour, wait) in community where dayHours.contains(hour) && result[hour] == nil {
            result[hour] = wait
        }

        let nowHour = calendar.component(.hour, from: now)
        if let currentWait, let nowCurve = parkCurve[nowHour], nowCurve > 0 {
            for hour in dayHours where result[hour] == nil {
                if let c = parkCurve[hour] {
                    result[hour] = max(0, Int((Double(currentWait) * c / nowCurve).rounded()))
                }
            }
        }
        // Today the current hour is what's posted now; for a future day the live wait is only a
        // reference for scaling the park curve
        if pinCurrentHour, let currentWait { result[nowHour] = currentWait }
        return result
    }
}

// MARK: - Builder

/// Greedy day planner: at each step, ride whatever costs least now (walk + expected wait),
/// nudged toward rides that are at their best right now and away from ones that get shorter
/// later. Fixed events (shows, dining) are never moved; rides only go where they fit.
enum DayPlanBuilder {
    static let defaultWalkMinutes = 8
    /// How much a ride's "it'll be shorter later" counts against doing it now
    static let laterPenalty = 0.5
    /// Extra cost (minutes) of an outdoor ride in an hour when rain is likely
    static let rainPenalty = 40.0

    static func walkMinutes(from: CLLocationCoordinate2D?, to: CLLocationCoordinate2D?) -> Int {
        guard let from, let to else { return defaultWalkMinutes }
        return WalkEstimate.minutes(from: from, to: to) ?? defaultWalkMinutes
    }

    /// - Parameter location: where the guest is now (live re-planning) — the first walk counts from here
    /// - Parameter wetHours: hours (0–23) when rain is likely (`RainForecastService`) — outdoor
    ///   rides are pushed out of them so indoor rides fill the storm
    static func build(rides: [PlanRide], fixed: [FixedEvent], start: Date, end: Date?,
                      from location: CLLocationCoordinate2D? = nil,
                      wetHours: Set<Int> = [],
                      calendar: Calendar = .current) -> DayPlan {
        var t = start
        var here: CLLocationCoordinate2D? = location
        var remaining = rides
        var events = fixed.filter { $0.start.addingTimeInterval(Double($0.minutes) * 60) > start }
            .sorted { $0.start < $1.start }
        var stops: [PlannedStop] = []

        while true {
            let nextEvent = events.first
            let limit = [nextEvent?.start, end].compactMap { $0 }.min()

            // Rides that finish before the next fixed event / end of day
            typealias Option = (index: Int, walk: Int, wait: Int, finish: Date, score: Double)
            let options = remaining.enumerated().compactMap { pair -> Option? in
                let (index, ride) = (pair.offset, pair.element)
                let walk = here == nil ? 0 : walkMinutes(from: here, to: ride.coordinate)
                let arrive = t.addingTimeInterval(Double(walk) * 60)
                let wait = ride.wait(at: arrive, calendar: calendar)
                let finish = arrive.addingTimeInterval(Double(wait + ride.rideMinutes) * 60)
                if let limit, finish > limit { return nil }
                let later = ride.bestWait(from: arrive, until: end, calendar: calendar)
                let wet = !ride.isIndoor && wetHours.contains(calendar.component(.hour, from: arrive))
                let score = Double(walk + wait) + laterPenalty * Double(max(0, wait - later))
                    + (wet ? rainPenalty : 0)
                return (index, walk, wait, finish, score)
            }

            if let pick = options.min(by: { $0.score < $1.score }) {
                let ride = remaining.remove(at: pick.index)
                stops.append(PlannedStop(title: ride.name, kind: "ride", rideId: ride.id, parkName: ride.parkName,
                                         start: t, walkMinutes: pick.walk, waitMinutes: pick.wait,
                                         totalMinutes: pick.walk + pick.wait + ride.rideMinutes))
                t = pick.finish
                here = ride.coordinate ?? here
                continue
            }

            if let event = nextEvent {
                events.removeFirst()
                stops.append(PlannedStop(title: event.title, kind: event.kind, rideId: nil, parkName: event.parkName,
                                         start: event.start, walkMinutes: 0, waitMinutes: 0, totalMinutes: event.minutes))
                t = max(t, event.start.addingTimeInterval(Double(event.minutes) * 60))
                continue
            }
            break
        }

        return DayPlan(stops: stops, unscheduled: remaining.map(\.name))
    }
}

// MARK: - Ordered plan (Apple Intelligence picks the order)

extension DayPlanBuilder {
    /// Rides in the given order; times come from each ride's wait profile. Fixed events never move:
    /// a ride that wouldn't finish before the next one goes after it. Rides past `end` are unscheduled.
    static func build(ordered rides: [PlanRide], fixed: [FixedEvent], start: Date, end: Date?,
                      from location: CLLocationCoordinate2D? = nil,
                      calendar: Calendar = .current) -> DayPlan {
        var t = start
        var here: CLLocationCoordinate2D? = location
        var events = fixed.filter { $0.start.addingTimeInterval(Double($0.minutes) * 60) > start }
            .sorted { $0.start < $1.start }
        var stops: [PlannedStop] = []
        var unscheduled: [String] = []

        func placeNextEvent() {
            let event = events.removeFirst()
            stops.append(PlannedStop(title: event.title, kind: event.kind, rideId: nil, parkName: event.parkName,
                                     start: event.start, walkMinutes: 0, waitMinutes: 0, totalMinutes: event.minutes))
            t = max(t, event.start.addingTimeInterval(Double(event.minutes) * 60))
        }

        for ride in rides {
            while true {
                let walk = here == nil ? 0 : walkMinutes(from: here, to: ride.coordinate)
                let arrive = t.addingTimeInterval(Double(walk) * 60)
                let wait = ride.wait(at: arrive, calendar: calendar)
                let finish = arrive.addingTimeInterval(Double(wait + ride.rideMinutes) * 60)
                if let next = events.first, finish > next.start {
                    placeNextEvent()      // do the show / meal first, then try this ride again
                    continue
                }
                if let end, finish > end {
                    unscheduled.append(ride.name)
                } else {
                    stops.append(PlannedStop(title: ride.name, kind: "ride", rideId: ride.id, parkName: ride.parkName,
                                             start: t, walkMinutes: walk, waitMinutes: wait,
                                             totalMinutes: walk + wait + ride.rideMinutes))
                    t = finish
                    here = ride.coordinate ?? here
                }
                break
            }
        }
        while !events.isEmpty { placeNextEvent() }
        return DayPlan(stops: stops, unscheduled: unscheduled)
    }
}

// MARK: - Constraints (from Apple Intelligence or plain text)

/// What the guest asked for, in planner terms. Filled by `PlannerAI` (Apple Intelligence) or,
/// on phones without it, by matching ride names in the text (`fromPlainText`).
struct PlanConstraints: Equatable {
    var mustRide: [String] = []
    var avoid: [String] = []
    /// "water", "coaster", "spinner", "simulator", "dark ride", "thrill"
    var avoidKinds: [String] = []
    var includeShows: [String] = []
    /// "HH:mm", 24-hour, park-local
    var startTime: String? = nil
    var endTime: String? = nil
    var fixedEvents: [Event] = []

    struct Event: Equatable {
        var title: String
        var time: String       // "HH:mm"
        var minutes: Int
    }

    /// Loose name match: punctuation-insensitive, either name containing the other.
    static func matches(_ query: String, _ name: String) -> Bool {
        let q = RideMetadata.normalize(query), n = RideMetadata.normalize(name)
        guard q.count >= 3, n.count >= 3 else { return false }
        return n.contains(q) || q.contains(n)
    }

    /// "18:30" → today at 6:30 PM (in `calendar`'s time zone)
    static func date(_ hhmm: String?, on day: Date, calendar: Calendar = .current) -> Date? {
        guard let hhmm else { return nil }
        let parts = hhmm.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// Ride ids to plan: named must-rides (or `fallback` if none were named), minus avoided rides/kinds.
    func selectRides(from rides: [(id: String, name: String, info: RideInfo?)], fallback: Set<String>) -> Set<String> {
        var chosen = Set(rides.filter { r in mustRide.contains { Self.matches($0, r.name) } }.map(\.id))
        if chosen.isEmpty { chosen = fallback }
        let avoided = Set(rides.filter { r in
            avoid.contains { Self.matches($0, r.name) } || Self.isAvoidedKind(r.info, kinds: avoidKinds)
        }.map(\.id))
        return chosen.subtracting(avoided)
    }

    static func isAvoidedKind(_ info: RideInfo?, kinds: [String]) -> Bool {
        guard let info, !kinds.isEmpty else { return false }
        return kinds.contains { kind in
            let k = kind.lowercased()
            if k.contains("water") { return info.type == .water }
            if k.contains("coaster") { return info.type == .coaster }
            if k.contains("spin") { return info.type == .spinner }
            if k.contains("simulator") || k.contains("motion") { return info.type == .simulator }
            if k.contains("dark") { return info.type == .darkRide }
            if k.contains("thrill") || k.contains("scary") || k.contains("intense") {
                return info.thrill == .thrilling || info.thrill == .extreme
            }
            return false
        }
    }

    /// "Dinner at Be Our Guest" → dining; anything else (snack, break, rest) → break
    static func eventKind(for title: String) -> String {
        let t = title.lowercased()
        return ["dinner", "lunch", "breakfast", "dining", "meal", "eat", "brunch"].contains { t.contains($0) }
            ? "dining" : "break"
    }

    /// No Apple Intelligence: pick up any ride or show names typed in the request.
    static func fromPlainText(_ text: String, rideNames: [String], showNames: [String]) -> PlanConstraints {
        let t = RideMetadata.normalize(text)
        var c = PlanConstraints()
        c.mustRide = rideNames.filter { t.contains(RideMetadata.normalize($0)) }
        c.includeShows = showNames.filter { t.contains(RideMetadata.normalize($0)) }
        return c
    }
}

// MARK: - Walking-aware ordering (pure)

/// Reordering picks so the day doesn't zig-zag across the park.
enum PlanOrdering {
    /// Walk between two rides (the builder's default when a location is missing)
    static func walk(_ a: PlanRide, _ b: PlanRide) -> Int {
        DayPlanBuilder.walkMinutes(from: a.coordinate, to: b.coordinate)
    }

    /// Minutes walked going through the rides in this order
    static func totalWalk(_ order: [PlanRide]) -> Int {
        zip(order, order.dropFirst()).reduce(0) { $0 + walk($1.0, $1.1) }
    }

    /// Keeps the first ride, then always goes to the nearest remaining one, then removes any
    /// crossings (2-opt). Rides without a location keep their order at the end.
    static func lessWalking(_ order: [PlanRide]) -> [PlanRide] {
        let located = order.filter { $0.coordinate != nil }
        let unlocated = order.filter { $0.coordinate == nil }
        guard located.count > 2, let first = located.first else { return order }

        var route = [first]
        var left = Array(located.dropFirst())
        while let last = route.last, !left.isEmpty {
            guard let i = left.indices.min(by: { walk(last, left[$0]) < walk(last, left[$1]) }) else { break }
            route.append(left.remove(at: i))
        }

        var improved = true
        while improved {
            improved = false
            for i in 1..<(route.count - 1) {
                for j in (i + 1)..<route.count {
                    var candidate = route
                    candidate[i...j].reverse()
                    if totalWalk(candidate) < totalWalk(route) {
                        route = candidate
                        improved = true
                    }
                }
            }
        }
        return route + unlocated
    }

    /// Must-Dos first, otherwise the same order
    static func mustDosFirst(_ order: [PlanRide], mustDo: Set<String>) -> [PlanRide] {
        order.filter { mustDo.contains($0.id) } + order.filter { !mustDo.contains($0.id) }
    }

    /// "keep rides close together", "less back and forth", "stop zig-zagging"…
    static func wantsLessWalking(_ request: String) -> Bool {
        let t = request.lowercased()
        return ["walk", "close to each other", "close together", "closer", "near each other", "nearby",
                "back and forth", "zig", "across the park", "same area", "one area", "cluster"]
            .contains { t.contains($0) }
    }
}

/// Groups rides a short walk apart into areas "A", "B", … (for Apple Intelligence's prompt).
enum PlanAreas {
    /// Rides within this many minutes' walk share an area
    static let sameAreaWalk = 5

    static func assign(_ rides: [PlanRide]) -> [String: String] {
        var parent = Array(rides.indices)
        func root(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { r = parent[r] }
            return r
        }
        for i in rides.indices where rides[i].coordinate != nil {
            for j in rides.indices where j > i && rides[j].coordinate != nil {
                if let a = rides[i].coordinate, let b = rides[j].coordinate,
                   let minutes = WalkEstimate.minutes(from: a, to: b), minutes <= sameAreaWalk {
                    parent[root(j)] = root(i)
                }
            }
        }
        var labels: [Int: String] = [:]
        var out: [String: String] = [:]
        for i in rides.indices where rides[i].coordinate != nil {
            let r = root(i)
            if labels[r] == nil {
                let n = labels.count
                labels[r] = n < 26 ? String(UnicodeScalar(UInt8(65 + n))) : "\(n + 1)"
            }
            out[rides[i].id] = labels[r]
        }
        return out
    }
}

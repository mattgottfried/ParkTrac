import AppIntents
import Foundation
import SwiftData

// MARK: - "What should I ride next?" (pure pick, unit tested)

enum NextRideAdvisor {
    struct Candidate: Equatable {
        let name: String
        let parkName: String
        let wait: Int
        /// Usual wait at this time when it's well above now (GoodTimeToRide)
        let usual: Int?
        let isMustDo: Bool
    }

    /// Best first: Must-Do running well below usual, any ride well below usual,
    /// Must-Dos by shortest wait, then everything else by shortest wait.
    static func pick(_ candidates: [Candidate], limit: Int = 2) -> [Candidate] {
        func rank(_ c: Candidate) -> Int {
            switch (c.usual != nil, c.isMustDo) {
            case (true, true):   return 0
            case (true, false):  return 1
            case (false, true):  return 2
            case (false, false): return 3
            }
        }
        return Array(candidates.sorted {
            let (a, b) = (rank($0), rank($1))
            if a != b { return a < b }
            if let ua = $0.usual, let ub = $1.usual { return (ua - $0.wait) > (ub - $1.wait) }
            return $0.wait < $1.wait
        }.prefix(limit))
    }

    static func dialog(_ picks: [Candidate]) -> String {
        guard let first = picks.first else {
            return "Nothing is posting a wait right now — the parks may be closed."
        }
        var text = "Go for \(first.name) at \(first.parkName) — \(first.wait) minutes now"
        if let usual = first.usual { text += ", usually about \(usual)" }
        text += "."
        if picks.count > 1 {
            let second = picks[1]
            text += " Also good: \(second.name), \(second.wait) minutes."
        }
        return text
    }
}

/// Resort + Must-Do list as the app last saved them (Siri can run without the UI).
private enum SiriContext {
    static var resort: ParkGroup {
        let raw = NSUbiquitousKeyValueStore.default.string(forKey: "selectedResortRaw")
            ?? UserDefaults.standard.string(forKey: "selectedResortRaw") ?? ""
        return ParkGroup(rawValue: raw) ?? .disney
    }

    static var mustDo: Set<String> {
        Set((NSUbiquitousKeyValueStore.default.array(forKey: "wishList") as? [String])
            ?? UserDefaults.standard.stringArray(forKey: "wishList") ?? [])
    }
}

struct WhatToRideNextIntent: AppIntent {
    static var title: LocalizedStringResource = "What Should I Ride Next?"
    static var description = IntentDescription("Suggests a ride with a short wait right now — Must-Dos and rides well below their usual wait first.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let resort = SiriContext.resort
        let mustDo = SiriContext.mustDo
        guard let parks = try? await ParkAPIService.shared.fetchParks(for: resort) else {
            return .result(dialog: "I couldn't load \(resort.shortName) wait times right now.")
        }

        var rides: [(ride: DisplayRide, parkName: String)] = []
        for park in parks {
            guard let entries = try? await ParkAPIService.shared.fetchLiveData(for: park.id) else { continue }
            rides += entries.filter { $0.entityType == "ATTRACTION" }
                .map { (ride: DisplayRide(live: $0, parkId: park.id, location: nil), parkName: park.name) }
        }

        // "Usually" comes from the waits this phone has recorded
        var history: [String: [(date: Date, wait: Int)]] = [:]
        if let container = try? PersistenceController.makeTelemetryContainer() {
            let since = Date.now.addingTimeInterval(-14 * 86_400)
            let records = (try? ModelContext(container).fetch(FetchDescriptor<WaitTimeRecord>(
                predicate: #Predicate { $0.recordedAt >= since }))) ?? []
            for r in records {
                if let w = r.waitMinutes { history[r.rideId, default: []].append((date: r.recordedAt, wait: w)) }
            }
        }

        let candidates = rides.compactMap { item -> NextRideAdvisor.Candidate? in
            guard item.ride.isOperating, let wait = item.ride.waitMinutes, wait > 0 else { return nil }
            let usual = GoodTimeToRide.usual(samples: history[item.ride.id] ?? [])
            let deal = GoodTimeToRide.deal(rideId: item.ride.id, wait: wait, isOperating: true, usual: usual)
            return .init(name: item.ride.name, parkName: item.parkName, wait: wait,
                         usual: deal?.usual.minutes, isMustDo: mustDo.contains(item.ride.id))
        }
        return .result(dialog: "\(NextRideAdvisor.dialog(NextRideAdvisor.pick(candidates)))")
    }
}

// MARK: - Parking

struct WhereDidIParkIntent: AppIntent {
    static var title: LocalizedStringResource = "Where Did I Park?"
    static var description = IntentDescription("Tells you where you saved your car today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let resort = SiriContext.resort
        guard let spot = ParkingService.shared.spot(for: resort) else {
            return .result(dialog: "You haven't saved a parking spot today. Say \"Save my parking spot in ThrillTrack\" when you park.")
        }
        let time = spot.savedAt.formatted(date: .omitted, time: .shortened)
        let place = spot.summary.isEmpty ? "a spot with GPS only — open ThrillTrack for directions" : spot.summary
        return .result(dialog: "You parked at \(place). Saved at \(time).")
    }
}

struct SaveParkingSpotIntent: AppIntent {
    static var title: LocalizedStringResource = "Save My Parking Spot"
    static var description = IntentDescription("Opens ThrillTrack's car locator so you can save where you parked.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.open(.parking)
        return .result()
    }
}

// MARK: - Plan my day

struct PlanMyDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan My Day"
    static var description = IntentDescription("Opens the Smart Planner with what you want to do, and ThrillTrack builds the schedule.")
    static var openAppWhenRun = true

    @Parameter(title: "What do you want to do?",
               requestValueDialog: "What should the plan include? For example, dinner at 6:30 and Space Mountain.")
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.plannerRequest = request
        DeepLinkRouter.shared.open(.planner)
        return .result()
    }
}

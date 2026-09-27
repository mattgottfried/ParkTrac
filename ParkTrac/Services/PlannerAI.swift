import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence (on-device Foundation Models, iOS 26+) turns a plain-English request —
/// "dinner at 6:30, want Seven Dwarfs and Space Mountain, no water rides" — into
/// `PlanConstraints`. The schedule itself is always built by `DayPlanBuilder`, so the model
/// only has to understand the request, never invent times or waits.
enum PlannerAI {
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Apple Intelligence isn't available on this iPhone." }
    }

    /// True on iOS 26+ devices with Apple Intelligence turned on and the model ready.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static func interpret(_ request: String, rideNames: [String], showNames: [String],
                          now: Date = .now) async throws -> PlanConstraints {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return try await Model.interpret(request, rideNames: rideNames, showNames: showNames, now: now)
        }
        #endif
        throw Failure.unavailable
    }

    static func prompt(_ request: String, rideNames: [String], showNames: [String], now: Date) -> String {
        let time = now.formatted(date: .omitted, time: .shortened)
        return """
        It is now \(time).
        Rides open right now: \(rideNames.joined(separator: "; "))
        Shows today: \(showNames.isEmpty ? "none" : showNames.joined(separator: "; "))

        Guest's request: \(request)
        """
    }

    static let instructions = """
    You help plan a theme park day. Turn the guest's request into planning constraints.
    Only use ride and show names exactly as they appear in the lists you're given.
    Times are 24-hour "HH:mm" in the park's local time; leave a time empty if the guest didn't give one.
    Dining reservations, meals and breaks the guest mentions become fixed events with a length in minutes \
    (meals 60–90, snacks or breaks 20–30 unless the guest says otherwise).
    Don't invent rides, shows or times the guest didn't ask for.
    """
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum Model {
    @Generable
    struct Request {
        @Guide(description: "Rides the guest wants to do, using names from the ride list")
        var mustRide: [String]
        @Guide(description: "Rides the guest wants to skip, using names from the ride list")
        var avoid: [String]
        @Guide(description: "Kinds of rides to skip, from: water, coaster, spinner, simulator, dark ride, thrill")
        var avoidKinds: [String]
        @Guide(description: "Shows the guest wants to see, using names from the show list")
        var includeShows: [String]
        @Guide(description: "When to start, 24-hour HH:mm, or empty")
        var startTime: String
        @Guide(description: "When to finish, 24-hour HH:mm, or empty")
        var endTime: String
        @Guide(description: "Meals, dining reservations or breaks at a set time")
        var fixedEvents: [Event]
    }

    @Generable
    struct Event {
        @Guide(description: "What it is, e.g. Dinner at Be Our Guest")
        var title: String
        @Guide(description: "Start time, 24-hour HH:mm")
        var time: String
        @Guide(description: "How long it takes in minutes")
        var minutes: Int
    }

    static func interpret(_ request: String, rideNames: [String], showNames: [String],
                          now: Date) async throws -> PlanConstraints {
        let session = LanguageModelSession(instructions: PlannerAI.instructions)
        let response = try await session.respond(
            to: PlannerAI.prompt(request, rideNames: rideNames, showNames: showNames, now: now),
            generating: Request.self)
        let r = response.content
        let blank: (String) -> String? = { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return PlanConstraints(
            mustRide: r.mustRide, avoid: r.avoid, avoidKinds: r.avoidKinds, includeShows: r.includeShows,
            startTime: blank(r.startTime), endTime: blank(r.endTime),
            fixedEvents: r.fixedEvents.map { .init(title: $0.title, time: $0.time, minutes: max(10, min($0.minutes, 240))) })
    }
}
#endif

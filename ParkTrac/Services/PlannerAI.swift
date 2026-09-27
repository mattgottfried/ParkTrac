import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence (on-device Foundation Models, iOS 26+) plans the order of the rides the
/// guest picked, from each ride's expected wait by hour, the shows and dining at set times, and
/// any notes ("dinner at 6:30, snack break at 3"). ThrillTrack then times the plan
/// (`DayPlanBuilder.build(ordered:)`), so the times always add up.
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

    // MARK: Input / output

    struct PlanInput {
        struct Ride {
            let name: String
            let waitsByHour: [Int: Int]
            let isMustDo: Bool
        }
        struct Fixed {
            let title: String
            let time: Date
        }
        var rides: [Ride]
        var shows: [Fixed]
        var dining: [Fixed]
        var start: Date
        var end: Date?
        var notes: String
        var interests: [String] = []
    }

    struct AIPlan: Equatable {
        var order: [String]
        var extraEvents: [PlanConstraints.Event]
        var summary: String
        /// Interests read from the notes ("we love coasters") — merged with the ones picked
        var interests: [String] = []
    }

    static func plan(_ input: PlanInput) async throws -> AIPlan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return try await Model.plan(input)
        }
        #endif
        throw Failure.unavailable
    }

    // MARK: Prompt (pure, unit tested)

    static let instructions = """
    You plan the order of a theme park day. You get the rides the guest picked, each with its expected \
    standby wait by hour, plus shows and dining at set times, when the day starts and ends, and the guest's notes.
    Return every picked ride exactly once, in the order to ride them, using the names exactly as given.
    Aim for short waits: put each ride where its expected wait is lowest, and do rides that get busier later \
    in the day first. Must-Do rides matter most. Follow the guest's notes about timing (for example \
    "ride it right before close" means put it last). Leave room for the shows and dining — ThrillTrack keeps \
    those at their times and works out the exact times of the rides.
    If the notes say what kinds of rides the party likes, list them in interests using only: thrill, coasters, \
    gentle, dark rides, water, simulators, shows.
    If the notes mention a meal or break at a time, add it to extraEvents with a 24-hour HH:mm time and a length \
    in minutes (meals 60–90, snacks or breaks 20–30 unless the guest says otherwise). If the notes don't mention \
    a meal or break, extraEvents must be empty. Never add dining the guest didn't ask for, and never add anything twice.
    Write summary as one or two friendly sentences explaining the plan.
    """

    static func hhmm(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "am" : "pm")"
    }

    static func prompt(_ input: PlanInput, calendar: Calendar = .current) -> String {
        let startHour = calendar.component(.hour, from: input.start)
        let endHour = input.end.map { calendar.component(.hour, from: $0) } ?? 22
        let hours = startHour <= endHour ? Array(startHour...endHour) : [startHour]

        let rides = input.rides.map { ride -> String in
            let waits = hours.compactMap { h in ride.waitsByHour[h].map { "\(hourLabel(h)) \($0)" } }
            return "- \(ride.name)\(ride.isMustDo ? " (Must-Do)" : ""): expected wait in minutes — "
                + (waits.isEmpty ? "unknown" : waits.joined(separator: ", "))
        }
        let fixed = (input.shows.map { "- Show: \($0.title) at \(hhmm($0.time, calendar: calendar))" }
            + input.dining.map { "- Dining: \($0.title) at \(hhmm($0.time, calendar: calendar))" })
        let notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        The day starts at \(hhmm(input.start, calendar: calendar))\(input.end.map { " and the park closes at \(hhmm($0, calendar: calendar))" } ?? "").

        Rides the guest picked:
        \(rides.joined(separator: "\n"))

        Set times:
        \(fixed.isEmpty ? "none" : fixed.joined(separator: "\n"))

        Interests: \(input.interests.isEmpty ? "none given" : input.interests.joined(separator: ", "))
        Guest's notes: \(notes.isEmpty ? "none" : notes)
        """
    }

    /// Keeps only the meals/breaks the guest actually asked for: the on-device model sometimes
    /// invents dining (or repeats it), so each event must share a word with the notes, and
    /// duplicates (same title, or the same kind at an overlapping time) are dropped.
    static func groundedExtras(_ events: [PlanConstraints.Event], notes: String) -> [PlanConstraints.Event] {
        let noteWords = words(notes)
        guard !noteWords.isEmpty else { return [] }
        var kept: [PlanConstraints.Event] = []
        for event in events {
            guard !words(event.title).isDisjoint(with: noteWords) else { continue }
            let kind = PlanConstraints.eventKind(for: event.title)
            let duplicate = kept.contains { other in
                RideMetadata.normalize(other.title) == RideMetadata.normalize(event.title)
                    || (PlanConstraints.eventKind(for: other.title) == kind && overlaps(other, event))
            }
            if !duplicate { kept.append(event) }
        }
        return kept
    }

    private static let fillerWords: Set<String> = ["the", "and", "for", "with", "our", "at", "a", "an", "in", "on", "to", "of"]

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 && !fillerWords.contains($0) })
    }

    private static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func overlaps(_ a: PlanConstraints.Event, _ b: PlanConstraints.Event) -> Bool {
        guard let sa = minutesOfDay(a.time), let sb = minutesOfDay(b.time) else { return false }
        return sa < sb + b.minutes && sb < sa + a.minutes
    }

    /// The model's order → rides: names matched loosely, each ride once, and any picked ride the
    /// model left out goes at the end (the guest's picks are always planned).
    static func resolveOrder(_ names: [String], rides: [PlanRide]) -> [PlanRide] {
        var result: [PlanRide] = []
        var used = Set<String>()
        for name in names {
            let match = rides.first { $0.name == name && !used.contains($0.id) }
                ?? rides.first { PlanConstraints.matches(name, $0.name) && !used.contains($0.id) }
            if let match {
                result.append(match)
                used.insert(match.id)
            }
        }
        return result + rides.filter { !used.contains($0.id) }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum Model {
    @Generable
    struct Response {
        @Guide(description: "Every picked ride name exactly once, in the order to ride them")
        var order: [String]
        @Guide(description: "Only meals or breaks the guest's notes ask for; empty when the notes don't mention one")
        var extraEvents: [Event]
        @Guide(description: "One or two friendly sentences explaining the plan")
        var summary: String
        @Guide(description: "Kinds of rides the notes say the party likes, from: thrill, coasters, gentle, dark rides, water, simulators, shows")
        var interests: [String]
    }

    @Generable
    struct Event {
        @Guide(description: "The meal or break in the guest's own words")
        var title: String
        @Guide(description: "Start time, 24-hour HH:mm")
        var time: String
        @Guide(description: "How long it takes in minutes")
        var minutes: Int
    }

    static func plan(_ input: PlannerAI.PlanInput) async throws -> PlannerAI.AIPlan {
        let session = LanguageModelSession(instructions: PlannerAI.instructions)
        let response = try await session.respond(to: PlannerAI.prompt(input), generating: Response.self)
        let r = response.content
        return PlannerAI.AIPlan(
            order: r.order,
            extraEvents: r.extraEvents.map { .init(title: $0.title, time: $0.time, minutes: max(10, min($0.minutes, 240))) },
            summary: r.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            interests: r.interests)
    }
}
#endif

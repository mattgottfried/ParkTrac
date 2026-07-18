import AppIntents
import Foundation
import SwiftData

/// Parses a dining confirmation email (piped in from a Shortcuts personal
/// automation, e.g. "when email received from Disney/Universal") and creates
/// a `DiningReservation`. A plain `AppIntent` — no `AppShortcutsProvider`
/// registration needed; any `AppIntent` automatically appears as an action in
/// the Shortcuts editor.
///
/// Parsing reuses data/tools already in the app rather than fragile
/// format-specific regex:
/// - date/time: `NSDataDetector` (robust across many real-world phrasings)
/// - restaurant name: substring match against `allSeedRestaurants` names
/// - party size / confirmation number: best-effort regex, both optional
struct AddDiningReservationFromEmailIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Dining Reservation from Email"
    static var description = IntentDescription(
        "Parse a dining confirmation email and create a reservation in ThrillTrack."
    )

    @Parameter(title: "Email Text")
    var emailText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add a dining reservation from \(\.$emailText)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = emailText

        guard let restaurant = Self.matchRestaurant(in: text) else {
            return .result(dialog: "I couldn't find a known restaurant name in that email. You can add the reservation manually in ThrillTrack.")
        }
        guard let date = Self.firstReservationDate(in: text) else {
            return .result(dialog: "I found \"\(restaurant.name)\" but couldn't read a date and time from the email. You can add it manually in ThrillTrack.")
        }

        let partySize = Self.parsePartySize(in: text) ?? 2
        let confirmation = Self.parseConfirmation(in: text) ?? ""

        let reservation = DiningReservation(
            restaurantName: restaurant.name,
            resort: restaurant.resort,
            date: date,
            partySize: partySize,
            confirmationNumber: confirmation
        )
        let context = ModelContext(PersistenceController.container)
        context.insert(reservation)
        try? context.save()

        // Refresh the dining countdown if this reservation is later today.
        LiveActivityManager.syncDiningActivity(context: context)

        let dateStr = date.formatted(date: .abbreviated, time: .shortened)
        var dialog = "Added a reservation at \(restaurant.name) on \(dateStr) for party of \(partySize)."
        if !confirmation.isEmpty {
            dialog += " Confirmation \(confirmation)."
        }
        return .result(dialog: "\(dialog)")
    }

    // MARK: - Parsing helpers

    /// The soonest future date/time found in the text; falls back to the first
    /// detected date if none are in the future (guards against a "sent" date
    /// being the only match).
    static func firstReservationDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        let dates = matches.compactMap { $0.date }
        let now = Date()
        let future = dates.filter { $0 > now }.sorted()
        return future.first ?? dates.first
    }

    /// Case-insensitive substring match against seeded restaurant names.
    /// Longest name first, so a longer, more specific name wins over a short
    /// name that happens to be a substring of it.
    static func matchRestaurant(in text: String) -> SeedRestaurant? {
        let haystack = text.lowercased()
        return allSeedRestaurants
            .sorted { $0.name.count > $1.name.count }
            .first { haystack.contains($0.name.lowercased()) }
    }

    static func parsePartySize(in text: String) -> Int? {
        firstCapture(in: text, pattern: "party of\\s+(\\d+)").flatMap { Int($0) }
    }

    static func parseConfirmation(in text: String) -> String? {
        firstCapture(in: text, pattern: "confirmation(?:\\s+number)?[:\\s#]+([A-Z0-9]{6,12})")
    }

    /// First capture group of `pattern` (case-insensitive), or nil.
    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captureRange])
    }
}

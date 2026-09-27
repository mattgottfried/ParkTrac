import AppIntents
import Foundation

/// Buttons on the Live Activities (iOS 17 `Button(intent:)`).
///
/// Shared between the app and the widget extension — this file must be compiled into BOTH
/// targets, like `ThrillTrackActivityAttributes.swift`. The system runs a `LiveActivityIntent`
/// in the app's process, where `LiveActivityActions.handler` (set in `ParkTracApp.init` by
/// `LiveActivityActionHandler`) does the work; the widget never sets it, so no app-only types
/// are needed here.
enum LiveActivityAction: Equatable {
    /// Park Day: mark the next ride done
    case done(rideId: String)
    /// Park Day: skip the next ride
    case skip(rideId: String)
    /// Stopwatch: I'm on the ride — stop the timer and log it
    case finishTimer
    /// Return time: used the Lightning Lane / return — tick it off and end the activity
    case usedReturn(rideId: String)
}

enum LiveActivityActions {
    nonisolated(unsafe) static var handler: ((LiveActivityAction) async -> Void)?
}

struct ParkDayDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done"
    static let isDiscoverable = false

    @Parameter(title: "Ride") var rideId: String

    init() {}
    init(rideId: String) { self.rideId = rideId }

    func perform() async throws -> some IntentResult {
        await LiveActivityActions.handler?(.done(rideId: rideId))
        return .result()
    }
}

struct ParkDaySkipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip"
    static let isDiscoverable = false

    @Parameter(title: "Ride") var rideId: String

    init() {}
    init(rideId: String) { self.rideId = rideId }

    func perform() async throws -> some IntentResult {
        await LiveActivityActions.handler?(.skip(rideId: rideId))
        return .result()
    }
}

struct FinishWaitTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I'm On"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveActivityActions.handler?(.finishTimer)
        return .result()
    }
}

struct UsedReturnIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Used It"
    static let isDiscoverable = false

    @Parameter(title: "Ride") var rideId: String

    init() {}
    init(rideId: String) { self.rideId = rideId }

    func perform() async throws -> some IntentResult {
        await LiveActivityActions.handler?(.usedReturn(rideId: rideId))
        return .result()
    }
}

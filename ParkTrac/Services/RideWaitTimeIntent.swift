import AppIntents

struct GetRideWaitTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Ride Wait Time"
    static var description = IntentDescription("Check the current wait time for a Disney World or Universal Orlando ride.")

    @Parameter(title: "Ride Name")
    var rideName: String

    static var parameterSummary: some ParameterSummary {
        Summary("What's the wait for \(\.$rideName)?")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let match = await RideLookupService.findRide(named: rideName) else {
            return .result(dialog: "I couldn't find a ride called \"\(rideName)\". Try the exact ride name, like Space Mountain.")
        }
        if match.isOperating, let minutes = match.waitMinutes {
            return .result(dialog: "\(match.name) at \(match.parkName) is posting a \(minutes) minute wait.")
        } else if match.status == "DOWN" {
            return .result(dialog: "\(match.name) is temporarily down right now.")
        } else {
            return .result(dialog: "\(match.name) is closed right now.")
        }
    }
}

struct ParkTracShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetRideWaitTimeIntent(),
            phrases: [
                "Check a ride wait time in \(.applicationName)",
                "What's the wait for a ride in \(.applicationName)"
            ],
            shortTitle: "Ride Wait Time",
            systemImageName: "clock.fill"
        )
    }
}

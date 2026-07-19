import WidgetKit

struct WaitTimeWidgetEntry: TimelineEntry {
    let date: Date
    let resortName: String
    let theme: ParkTheme
    let crowdLevel: CrowdLevel?
    let topRides: [(name: String, wait: Int)]
}

struct WaitTimeTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WaitTimeWidgetEntry {
        WaitTimeWidgetEntry(
            date: .now,
            resortName: ParkGroup.disney.rawValue,
            theme: ParkGroup.disney.theme,
            crowdLevel: .moderate,
            topRides: [("Space Mountain", 25), ("Big Thunder Mountain Railroad", 15), ("Haunted Mansion", 10)]
        )
    }

    func snapshot(for configuration: WaitTimeWidgetConfigIntent, in context: Context) async -> WaitTimeWidgetEntry {
        await fetchEntry(for: configuration.resort.parkGroup)
    }

    func timeline(for configuration: WaitTimeWidgetConfigIntent, in context: Context) async -> Timeline<WaitTimeWidgetEntry> {
        let entry = await fetchEntry(for: configuration.resort.parkGroup)
        // WidgetKit budgets refresh cadence itself; this is a floor, not a guarantee.
        let nextRefresh = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func fetchEntry(for group: ParkGroup) async -> WaitTimeWidgetEntry {
        guard let parks = try? await ParkAPIService.shared.fetchDestinationChildren(destinationId: group.destinationId),
              !parks.isEmpty else {
            return WaitTimeWidgetEntry(date: .now, resortName: group.rawValue, theme: group.theme, crowdLevel: nil, topRides: [])
        }

        var allLive: [LiveDataEntry] = []
        await withTaskGroup(of: [LiveDataEntry].self) { taskGroup in
            for park in parks {
                taskGroup.addTask {
                    (try? await ParkAPIService.shared.fetchLiveData(for: park.id)) ?? []
                }
            }
            for await entries in taskGroup {
                allLive.append(contentsOf: entries)
            }
        }

        let operating = allLive.filter { $0.entityType == "ATTRACTION" && $0.isOperating && $0.waitMinutes != nil }
        let top = operating.sorted { ($0.waitMinutes ?? 0) < ($1.waitMinutes ?? 0) }.prefix(3)
        let crowdLevel: CrowdLevel?
        if operating.isEmpty {
            crowdLevel = nil
        } else {
            let avg = Double(operating.reduce(0) { $0 + ($1.waitMinutes ?? 0) }) / Double(operating.count)
            crowdLevel = CrowdLevel.from(averageWait: avg)
        }

        return WaitTimeWidgetEntry(
            date: .now,
            resortName: group.rawValue,
            theme: group.theme,
            crowdLevel: crowdLevel,
            topRides: top.map { ($0.name, $0.waitMinutes ?? 0) }
        )
    }
}

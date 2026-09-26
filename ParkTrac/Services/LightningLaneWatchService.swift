import Foundation

// MARK: - Watch

/// "Tell me when a Lightning Lane Multi Pass return opens for this ride inside my window."
///
/// Watches are notify-only: the app never books. Stored per device (UserDefaults, not
/// CloudKit) so two phones on the same Apple ID don't both fire the same alert, and they
/// only apply to the day they were created.
struct LightningLaneWatch: Codable, Identifiable, Equatable {
    var id = UUID()
    var rideId: String
    var rideName: String
    var parkId: String
    /// Optional so watches saved before this field existed still decode
    var parkName: String?
    /// Start of the day this watch applies to
    var day: Date
    /// Earliest acceptable return time (on `day`)
    var windowStart: Date
    /// Latest acceptable return time (on `day`)
    var windowEnd: Date
    /// Earliest return we've already alerted about — only an earlier one alerts again
    var lastNotifiedStart: Date?

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    func accepts(_ returnStart: Date) -> Bool {
        returnStart >= windowStart && returnStart <= windowEnd
    }

    var windowText: String {
        "\(windowStart.formatted(date: .omitted, time: .shortened))–\(windowEnd.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Service

@Observable
final class LightningLaneWatchService {
    static let shared = LightningLaneWatchService()

    private static let storageKey = "lightningLaneWatches"

    /// Today's watches (older days are dropped on load and on every check)
    private(set) var watches: [LightningLaneWatch] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([LightningLaneWatch].self, from: data) {
            watches = saved.filter(\.isToday)
        }
    }

    var hasActiveWatches: Bool { watches.contains(where: \.isToday) }

    func watch(for rideId: String) -> LightningLaneWatch? {
        watches.first { $0.rideId == rideId && $0.isToday }
    }

    /// Adds or replaces the watch for this ride. Changing the window re-arms the alert.
    func save(_ watch: LightningLaneWatch) {
        var watch = watch
        if let existing = watches.first(where: { $0.id == watch.id }),
           existing.windowStart != watch.windowStart || existing.windowEnd != watch.windowEnd {
            watch.lastNotifiedStart = nil
        }
        watches.removeAll { $0.id == watch.id || $0.rideId == watch.rideId }
        watches.append(watch)
        persist()
    }

    func remove(rideId: String) {
        watches.removeAll { $0.rideId == rideId }
        persist()
    }

    func remove(id: UUID) {
        watches.removeAll { $0.id == id }
        persist()
    }

    /// Called after every live-data refresh (foreground and background). Fires a
    /// notification when a Multi Pass return opens inside a watch's window, and again
    /// only if an even earlier return shows up later.
    @MainActor
    func check(rides: [DisplayRide]) {
        let before = watches
        watches = watches.filter(\.isToday)
        guard !watches.isEmpty else {
            if before != watches { persist() }
            return
        }

        let byId = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in watches.indices {
            let watch = watches[index]
            guard let ride = byId[watch.rideId],
                  let ll = ride.multiPass, ll.isAvailable,
                  let start = ll.returnStart,
                  watch.accepts(start) else { continue }
            if let last = watch.lastNotifiedStart, start >= last { continue }

            NotificationService.shared.fireLightningLaneOpening(
                watch: watch, returnStart: start, returnEnd: ll.returnEnd, previous: watch.lastNotifiedStart)
            watches[index].lastNotifiedStart = start
        }
        if before != watches { persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(watches) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

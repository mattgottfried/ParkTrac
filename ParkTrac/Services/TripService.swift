import Foundation

// MARK: - Trip

/// One upcoming trip (e.g. Japan in November): dates, a pre-trip checklist and a countdown.
/// Stored in iCloud key-value storage so both phones share the dates and checklist.
struct Trip: Codable, Equatable {
    var name: String
    var startDate: Date
    var endDate: Date
    /// ParkGroup raw values visited on this trip (drives the yen converter and defaults)
    var resortsRaw: [String]
    var checklist: [ChecklistItem]

    var resorts: [ParkGroup] { resortsRaw.compactMap(ParkGroup.init(rawValue:)) }
    var isJapan: Bool { resorts.contains { !$0.isOrlando } }

    struct ChecklistItem: Codable, Equatable, Identifiable {
        var id = UUID()
        var title: String
        var isDone = false
    }

    /// Starting list for Japan — edit freely in the app.
    static let japanChecklist: [String] = [
        "Passports valid for the whole trip",
        "Visit Japan Web filled in (immigration & customs QR codes)",
        "Tokyo Disney Resort tickets bought (they're date-specific)",
        "Tokyo Disney Resort App set up (Premier Access, Priority Pass, Standby Pass)",
        "USJ tickets + Express Pass bought",
        "USJ app installed (Area Timed Entry for Super Nintendo World)",
        "Shinkansen tickets Tokyo ↔ Osaka",
        "Suica or PASMO added to Apple Wallet",
        "eSIM or pocket Wi-Fi",
        "Some yen in cash",
        "No-foreign-fee card; bank told about travel",
        "Travel insurance",
        "Hotel and flight confirmations saved offline",
    ]

    static func japan(start: Date, end: Date) -> Trip {
        Trip(name: "Japan", startDate: start, endDate: end,
             resortsRaw: [ParkGroup.tokyoDisney.rawValue, ParkGroup.universalJapan.rawValue],
             checklist: japanChecklist.map { ChecklistItem(title: $0) })
    }
}

// MARK: - Countdown (pure)

enum TripCountdown: Equatable {
    case upcoming(days: Int)
    case during(day: Int, of: Int)
    case over

    static func status(start: Date, end: Date, now: Date = .now, calendar: Calendar = .current) -> TripCountdown {
        let today = calendar.startOfDay(for: now)
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: max(start, end))
        if today < first {
            return .upcoming(days: calendar.dateComponents([.day], from: today, to: first).day ?? 0)
        }
        if today > last { return .over }
        let day = (calendar.dateComponents([.day], from: first, to: today).day ?? 0) + 1
        let total = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        return .during(day: day, of: total)
    }

    /// "Japan in 42 days" / "Japan is tomorrow!" / "Japan · Day 3 of 8"
    func text(tripName: String) -> String? {
        switch self {
        case .upcoming(let days) where days == 1: return "\(tripName) is tomorrow!"
        case .upcoming(let days): return "\(tripName) in \(days) days"
        case .during(let day, let total): return "\(tripName) · Day \(day) of \(total)"
        case .over: return nil
        }
    }
}

// MARK: - Service

@Observable
final class TripService {
    static let shared = TripService()

    private static let storageKey = "tripPlan"
    private let icloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    private(set) var trip: Trip?

    private init() {
        trip = Self.decode(icloud.data(forKey: Self.storageKey) ?? defaults.data(forKey: Self.storageKey))
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.trip = Self.decode(self.icloud.data(forKey: Self.storageKey))
        }
    }

    var countdown: TripCountdown? {
        trip.map { TripCountdown.status(start: $0.startDate, end: $0.endDate) }
    }

    /// Shown on My Day until the trip is over
    var countdownText: String? {
        guard let trip, let countdown else { return nil }
        return countdown.text(tripName: trip.name)
    }

    func save(_ trip: Trip?) {
        self.trip = trip
        if let data = trip.flatMap(Self.encode) {
            icloud.set(data, forKey: Self.storageKey)
            defaults.set(data, forKey: Self.storageKey)
        } else {
            icloud.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    func update(_ change: (inout Trip) -> Void) {
        guard var trip else { return }
        change(&trip)
        save(trip)
    }

    static func encode(_ trip: Trip) -> Data? { try? JSONEncoder().encode(trip) }
    static func decode(_ data: Data?) -> Trip? { data.flatMap { try? JSONDecoder().decode(Trip.self, from: $0) } }
}

// MARK: - Yen ↔ dollar

/// Spending at Japan resorts is logged in yen; this shows the rough dollar amount beside it.
/// The rate refreshes from a free exchange-rate API at most daily, or can be set by hand.
@Observable
final class CurrencyConverter {
    static let shared = CurrencyConverter()

    static let defaultYenPerDollar = 150.0
    private let defaults = UserDefaults.standard

    /// ¥ for $1
    private(set) var yenPerDollar: Double
    private(set) var updatedAt: Date?
    /// Set by hand — don't overwrite from the network
    private(set) var isManual: Bool

    private init() {
        let saved = defaults.double(forKey: "yenPerDollar")
        yenPerDollar = saved > 0 ? saved : Self.defaultYenPerDollar
        updatedAt = defaults.object(forKey: "yenPerDollarUpdated") as? Date
        isManual = defaults.bool(forKey: "yenPerDollarManual")
    }

    func setManual(_ rate: Double) {
        guard rate > 0 else { return }
        yenPerDollar = rate
        isManual = true
        updatedAt = .now
        persist()
    }

    func useLiveRate() async {
        isManual = false
        defaults.set(false, forKey: "yenPerDollarManual")
        await refresh(force: true)
    }

    /// Fetches USD→JPY (ECB rates via Frankfurter, no key). Keeps the last rate on failure.
    func refresh(force: Bool = false) async {
        guard !isManual else { return }
        if !force, let updatedAt, Date.now.timeIntervalSince(updatedAt) < 20 * 3600 { return }
        for url in ["https://api.frankfurter.dev/v1/latest?base=USD&symbols=JPY",
                    "https://api.frankfurter.app/latest?from=USD&to=JPY"] {
            guard let u = URL(string: url),
                  let result = try? await URLSession.shared.data(from: u),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let rate = Self.parseRate(result.0) else { continue }
            await MainActor.run {
                self.yenPerDollar = rate
                self.updatedAt = .now
                self.persist()
            }
            return
        }
    }

    static func parseRate(_ data: Data) -> Double? {
        struct Response: Decodable { let rates: [String: Double] }
        guard let rate = (try? JSONDecoder().decode(Response.self, from: data))?.rates["JPY"], rate > 0 else { return nil }
        return rate
    }

    /// "≈ $12.34" for a yen amount
    static func dollarsText(yen: Double, yenPerDollar: Double) -> String {
        let dollars = yen / yenPerDollar
        return "≈ " + dollars.formatted(.currency(code: "USD").precision(.fractionLength(dollars < 100 ? 2 : 0)))
    }

    func dollarsText(yen: Double) -> String { Self.dollarsText(yen: yen, yenPerDollar: yenPerDollar) }

    private func persist() {
        defaults.set(yenPerDollar, forKey: "yenPerDollar")
        defaults.set(isManual, forKey: "yenPerDollarManual")
        defaults.set(updatedAt, forKey: "yenPerDollarUpdated")
    }
}

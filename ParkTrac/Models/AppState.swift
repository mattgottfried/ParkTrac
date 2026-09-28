import SwiftUI
import Observation

// MARK: - Pass Tier Enums

enum DisneyPassTier: String, CaseIterable, Codable {
    case none       = "None"
    case pixieDust  = "Pixie Dust Pass"
    case pirate     = "Pirate Pass"
    case sorcerer   = "Sorcerer Pass"
    case incredi    = "Incredi-Pass"
}

enum UniversalPassTier: String, CaseIterable, Codable {
    case none       = "None"
    case seasonal   = "Seasonal Pass"
    case select     = "Select Pass"
    case power      = "Power Pass"
    case preferred  = "Preferred Pass"
    case premier    = "Premier Pass"
}

enum UniversalExpressType: String, CaseIterable {
    case none      = "None"
    case expressNow = "Express Now"
}

// MARK: - AppState

@Observable
final class AppState {
    // iCloud Key-Value Store — syncs preferences across devices automatically via Apple ID
    private let icloud = NSUbiquitousKeyValueStore.default

    var selectedResort: ParkGroup {
        didSet { icloud.set(selectedResort.rawValue, forKey: "selectedResortRaw") }
    }
    var showResortPicker: Bool = false

    // MARK: - Persisted Settings (iCloud-synced)

    var defaultMapIsSatellite: Bool {
        didSet { icloud.set(defaultMapIsSatellite, forKey: "defaultMapIsSatellite") }
    }
    var sortRidesAlphabetically: Bool {
        didSet { icloud.set(sortRidesAlphabetically, forKey: "sortRidesAlphabetically") }
    }

    /// This trip's spending target per resort (`ParkGroup.rawValue`), in that resort's currency. 0 = not set.
    var tripBudgets: [String: Double] {
        didSet { icloud.set(tripBudgets, forKey: "tripBudgets") }
    }
    func tripBudget(for resort: ParkGroup) -> Double { tripBudgets[resort.rawValue] ?? 0 }
    func setTripBudget(_ value: Double, for resort: ParkGroup) { tripBudgets[resort.rawValue] = value }

    /// Names shown on the two dining/hotel rating columns (stored as `mattRating` / `wifeRating`).
    var raterOneName: String {
        didSet { icloud.set(raterOneName, forKey: "raterOneName") }
    }
    var raterTwoName: String {
        didSet { icloud.set(raterTwoName, forKey: "raterTwoName") }
    }
    static let defaultRaterOneName = "Matt"
    static let defaultRaterTwoName = "Heather"
    /// Display labels — fall back to the defaults if a name is cleared.
    var raterOneLabel: String {
        let t = raterOneName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? Self.defaultRaterOneName : t
    }
    var raterTwoLabel: String {
        let t = raterTwoName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? Self.defaultRaterTwoName : t
    }

    var wishList: Set<String> {
        didSet { icloud.set(Array(wishList), forKey: "wishList") }
    }

    // MARK: - Annual Pass

    var disneyPassTier: DisneyPassTier {
        didSet { icloud.set(disneyPassTier.rawValue, forKey: "disneyPassTier") }
    }
    var disneyPassExpiry: Date? {
        didSet {
            if let d = disneyPassExpiry {
                icloud.set(d.timeIntervalSince1970, forKey: "disneyPassExpiry")
            } else {
                icloud.removeObject(forKey: "disneyPassExpiry")
            }
        }
    }
    var universalPassTier: UniversalPassTier {
        didSet { icloud.set(universalPassTier.rawValue, forKey: "universalPassTier") }
    }
    var universalPassExpiry: Date? {
        didSet {
            if let d = universalPassExpiry {
                icloud.set(d.timeIntervalSince1970, forKey: "universalPassExpiry")
            } else {
                icloud.removeObject(forKey: "universalPassExpiry")
            }
        }
    }

    // MARK: - Active Stopwatch Timer

    var activeTimerRideId: String? {
        didSet { UserDefaults.standard.set(activeTimerRideId, forKey: "activeTimerRideId") }
    }
    var activeTimerStart: Date? {
        didSet { UserDefaults.standard.set(activeTimerStart?.timeIntervalSince1970, forKey: "activeTimerStart") }
    }

    // Additional timer context (for WaitTimerBanner)
    var timerRideName: String {
        didSet { UserDefaults.standard.set(timerRideName, forKey: "timerRideName") }
    }
    var timerPostedMinutes: Int {
        didSet { UserDefaults.standard.set(timerPostedMinutes, forKey: "timerPostedMinutes") }
    }
    var timerResort: String {
        didSet { UserDefaults.standard.set(timerResort, forKey: "timerResort") }
    }

    // Aliases used by WaitTimerBanner
    var timerStartDate: Date? { activeTimerStart }
    var timerRideId: String? { activeTimerRideId }

    func clearTimer() {
        activeTimerRideId = nil
        activeTimerStart = nil
        timerRideName = ""
        timerPostedMinutes = 0
        timerResort = ""
        LiveActivityManager.endWaitTimer()
    }

    // MARK: - Pass Cost (for savings calculation)

    var disneyPassCost: Double {
        didSet { UserDefaults.standard.set(disneyPassCost, forKey: "disneyPassCost") }
    }
    var universalPassCost: Double {
        didSet { UserDefaults.standard.set(universalPassCost, forKey: "universalPassCost") }
    }

    // MARK: - Pass Accessibility / Express features

    var hasLightningLane: Bool {
        didSet { UserDefaults.standard.set(hasLightningLane, forKey: "hasLightningLane") }
    }
    var hasDAS: Bool {
        didSet { UserDefaults.standard.set(hasDAS, forKey: "hasDAS") }
    }
    var hasAAP: Bool {
        didSet { UserDefaults.standard.set(hasAAP, forKey: "hasAAP") }
    }
    var universalExpressType: UniversalExpressType {
        didSet { UserDefaults.standard.set(universalExpressType.rawValue, forKey: "universalExpressType") }
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    var partyMembers: [String] {
        didSet { UserDefaults.standard.set(partyMembers, forKey: "partyMembers") }
    }

    // MARK: - Today's Guests (keyed by date, auto-resets)

    /// Names of guests coming today (Guest.name). Stored — not computed from UserDefaults —
    /// so SwiftUI observes changes; persisted per day and reset by `reloadTodayGuestsIfNewDay()`.
    /// (Previously keyed by `persistentModelID.hashValue`, which Swift re-randomizes every launch.)
    var todayGuestNames: [String] = [] {
        didSet { UserDefaults.standard.set(todayGuestNames, forKey: Self.guestKey(for: todayGuestDay)) }
    }
    private var todayGuestDay: String = AppState.dayStamp(.now)

    /// Call when the app becomes active: starts a fresh guest list on a new day.
    func reloadTodayGuestsIfNewDay() {
        let today = Self.dayStamp(.now)
        guard today != todayGuestDay else { return }
        todayGuestDay = today
        todayGuestNames = UserDefaults.standard.stringArray(forKey: Self.guestKey(for: today)) ?? []
    }

    private static func guestKey(for day: String) -> String { "todayGuestNames-\(day)" }

    private static func dayStamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    /// Party names from onboarding, minus the "Me" placeholder
    var namedPartyMembers: [String] {
        partyMembers.filter { !$0.isEmpty && $0 != "Me" }
    }

    init() {
        let kv = NSUbiquitousKeyValueStore.default
        let ud = UserDefaults.standard

        // iCloud-synced prefs: read iCloud first, fall back to UserDefaults for one-time migration
        let savedResort = kv.string(forKey: "selectedResortRaw") ?? ud.string(forKey: "selectedResortRaw") ?? ""
        self.selectedResort = ParkGroup(rawValue: savedResort) ?? .disney

        self.defaultMapIsSatellite = kv.object(forKey: "defaultMapIsSatellite") != nil
            ? kv.bool(forKey: "defaultMapIsSatellite")
            : ud.bool(forKey: "defaultMapIsSatellite")

        self.sortRidesAlphabetically = kv.object(forKey: "sortRidesAlphabetically") != nil
            ? kv.bool(forKey: "sortRidesAlphabetically")
            : ud.bool(forKey: "sortRidesAlphabetically")

        self.tripBudgets = (kv.dictionary(forKey: "tripBudgets") as? [String: Double])
            ?? (ud.dictionary(forKey: "tripBudgets") as? [String: Double]) ?? [:]

        self.raterOneName = kv.string(forKey: "raterOneName") ?? AppState.defaultRaterOneName
        self.raterTwoName = kv.string(forKey: "raterTwoName") ?? AppState.defaultRaterTwoName

        let wishArr = (kv.array(forKey: "wishList") as? [String]) ?? ud.stringArray(forKey: "wishList") ?? []
        self.wishList = Set(wishArr)

        let disneyRaw = kv.string(forKey: "disneyPassTier") ?? ud.string(forKey: "disneyPassTier") ?? ""
        self.disneyPassTier = DisneyPassTier(rawValue: disneyRaw) ?? .none

        let universalRaw = kv.string(forKey: "universalPassTier") ?? ud.string(forKey: "universalPassTier") ?? ""
        self.universalPassTier = UniversalPassTier(rawValue: universalRaw) ?? .none

        // Disney pass expiry
        if kv.object(forKey: "disneyPassExpiry") != nil {
            let ts = kv.double(forKey: "disneyPassExpiry")
            self.disneyPassExpiry = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        } else if ud.object(forKey: "disneyPassExpiry") != nil {
            self.disneyPassExpiry = Date(timeIntervalSince1970: ud.double(forKey: "disneyPassExpiry"))
        }

        // Universal pass expiry
        if kv.object(forKey: "universalPassExpiry") != nil {
            let ts = kv.double(forKey: "universalPassExpiry")
            self.universalPassExpiry = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        } else if ud.object(forKey: "universalPassExpiry") != nil {
            self.universalPassExpiry = Date(timeIntervalSince1970: ud.double(forKey: "universalPassExpiry"))
        }

        // Device-local timer state (UserDefaults only)
        activeTimerRideId = ud.string(forKey: "activeTimerRideId")
        let ts = ud.double(forKey: "activeTimerStart")
        activeTimerStart = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        timerRideName = ud.string(forKey: "timerRideName") ?? ""
        timerPostedMinutes = ud.integer(forKey: "timerPostedMinutes")
        timerResort = ud.string(forKey: "timerResort") ?? ""

        // Onboarding + party (device-local)
        hasCompletedOnboarding = ud.bool(forKey: "hasCompletedOnboarding")
        partyMembers = ud.stringArray(forKey: "partyMembers") ?? []
        todayGuestNames = ud.stringArray(forKey: AppState.guestKey(for: AppState.dayStamp(.now))) ?? []

        // Pass features (device-local)
        disneyPassCost = ud.double(forKey: "disneyPassCost")
        universalPassCost = ud.double(forKey: "universalPassCost")
        hasLightningLane = ud.bool(forKey: "hasLightningLane")
        hasDAS = ud.bool(forKey: "hasDAS")
        hasAAP = ud.bool(forKey: "hasAAP")
        let expressRaw = ud.string(forKey: "universalExpressType") ?? ""
        universalExpressType = UniversalExpressType(rawValue: expressRaw) ?? .none

        // Listen for changes pushed from other devices
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kv,
            queue: .main
        ) { [weak self] _ in self?.reloadFromiCloud() }

        // The stopwatch was stopped from its Live Activity ("I'm On")
        NotificationCenter.default.addObserver(
            forName: .waitTimerChangedExternally, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let ud = UserDefaults.standard
            self.activeTimerRideId = ud.string(forKey: "activeTimerRideId")
            let ts = ud.double(forKey: "activeTimerStart")
            self.activeTimerStart = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
            self.timerRideName = ud.string(forKey: "timerRideName") ?? ""
            self.timerPostedMinutes = ud.integer(forKey: "timerPostedMinutes")
            self.timerResort = ud.string(forKey: "timerResort") ?? ""
        }
    }

    func toggleWish(_ rideId: String) {
        if wishList.contains(rideId) { wishList.remove(rideId) }
        else { wishList.insert(rideId) }
    }

    // MARK: - Reload from iCloud (fires when another device writes new values)

    private func reloadFromiCloud() {
        let kv = NSUbiquitousKeyValueStore.default
        if let raw = kv.string(forKey: "selectedResortRaw"), let r = ParkGroup(rawValue: raw) { selectedResort = r }
        if kv.object(forKey: "defaultMapIsSatellite") != nil { defaultMapIsSatellite = kv.bool(forKey: "defaultMapIsSatellite") }
        if kv.object(forKey: "sortRidesAlphabetically") != nil { sortRidesAlphabetically = kv.bool(forKey: "sortRidesAlphabetically") }
        if let dict = kv.dictionary(forKey: "tripBudgets") as? [String: Double] { tripBudgets = dict }
        if let name = kv.string(forKey: "raterOneName") { raterOneName = name }
        if let name = kv.string(forKey: "raterTwoName") { raterTwoName = name }
        if let arr = kv.array(forKey: "wishList") as? [String] { wishList = Set(arr) }
        if let raw = kv.string(forKey: "disneyPassTier"), let t = DisneyPassTier(rawValue: raw) { disneyPassTier = t }
        if let raw = kv.string(forKey: "universalPassTier"), let t = UniversalPassTier(rawValue: raw) { universalPassTier = t }
        let dts = kv.double(forKey: "disneyPassExpiry"); disneyPassExpiry = dts > 0 ? Date(timeIntervalSince1970: dts) : nil
        let uts = kv.double(forKey: "universalPassExpiry"); universalPassExpiry = uts > 0 ? Date(timeIntervalSince1970: uts) : nil
    }
}

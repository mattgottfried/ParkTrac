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

// MARK: - AppState

@Observable
final class AppState {
    var selectedResort: ParkGroup {
        didSet { UserDefaults.standard.set(selectedResort.rawValue, forKey: "selectedResortRaw") }
    }
    var showResortPicker: Bool = false

    // MARK: - Persisted Settings

    var defaultMapIsSatellite: Bool {
        didSet { UserDefaults.standard.set(defaultMapIsSatellite, forKey: "defaultMapIsSatellite") }
    }
    var sortRidesAlphabetically: Bool {
        didSet { UserDefaults.standard.set(sortRidesAlphabetically, forKey: "sortRidesAlphabetically") }
    }

    var wishList: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(wishList), forKey: "wishList")
        }
    }

    // MARK: - Annual Pass

    var disneyPassTier: DisneyPassTier {
        didSet { UserDefaults.standard.set(disneyPassTier.rawValue, forKey: "disneyPassTier") }
    }
    var disneyPassExpiry: Date? {
        didSet {
            if let d = disneyPassExpiry {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: "disneyPassExpiry")
            } else {
                UserDefaults.standard.removeObject(forKey: "disneyPassExpiry")
            }
        }
    }
    var universalPassTier: UniversalPassTier {
        didSet { UserDefaults.standard.set(universalPassTier.rawValue, forKey: "universalPassTier") }
    }
    var universalPassExpiry: Date? {
        didSet {
            if let d = universalPassExpiry {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: "universalPassExpiry")
            } else {
                UserDefaults.standard.removeObject(forKey: "universalPassExpiry")
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

    // MARK: - Today's Guests (keyed by date, auto-resets)

    var todayGuestIds: [String] {
        get {
            let key = todayGuestKey
            return UserDefaults.standard.stringArray(forKey: key) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: todayGuestKey)
        }
    }

    private var todayGuestKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return "todayGuests-\(fmt.string(from: .now))"
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedResortRaw") ?? ""
        self.selectedResort    = ParkGroup(rawValue: saved) ?? .disney
        self.defaultMapIsSatellite   = UserDefaults.standard.bool(forKey: "defaultMapIsSatellite")
        self.sortRidesAlphabetically = UserDefaults.standard.bool(forKey: "sortRidesAlphabetically")
        self.wishList = Set(UserDefaults.standard.stringArray(forKey: "wishList") ?? [])

        let disneyRaw = UserDefaults.standard.string(forKey: "disneyPassTier") ?? ""
        self.disneyPassTier = DisneyPassTier(rawValue: disneyRaw) ?? .none
        let universalRaw = UserDefaults.standard.string(forKey: "universalPassTier") ?? ""
        self.universalPassTier = UniversalPassTier(rawValue: universalRaw) ?? .none

        if UserDefaults.standard.object(forKey: "disneyPassExpiry") != nil {
            self.disneyPassExpiry = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "disneyPassExpiry"))
        }
        if UserDefaults.standard.object(forKey: "universalPassExpiry") != nil {
            self.universalPassExpiry = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "universalPassExpiry"))
        }

        activeTimerRideId = UserDefaults.standard.string(forKey: "activeTimerRideId")
        let ts = UserDefaults.standard.double(forKey: "activeTimerStart")
        activeTimerStart = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    func toggleWish(_ rideId: String) {
        if wishList.contains(rideId) { wishList.remove(rideId) }
        else { wishList.insert(rideId) }
    }
}

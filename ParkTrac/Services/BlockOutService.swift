import Foundation

// MARK: - BlockOutService
// Exact blockout dates sourced from blockoutcalendars.com (retrieved Jun 2, 2026).
// Uses date-string lookup sets for accuracy — no algorithmic approximations.

enum BlockOutService {

    // MARK: - Disney

    static func isBlockedOut(_ date: Date, disney tier: DisneyPassTier) -> Bool {
        switch tier {
        case .none:      return false
        case .incredi:   return false          // no blockouts
        case .sorcerer:  return disneyDateKey(date, in: sorcererDates)
        case .pirate:    return disneyDateKey(date, in: pirateDates)
        case .pixieDust: return disneyDateKey(date, in: pixieDustDates)
        }
    }

    // MARK: - Universal

    /// Returns true when the date is blocked for the primary Universal parks
    /// (USF + IOA ± Epic Universe). Volcano-Bay-only blockouts are ignored since
    /// most visitors are going to the main parks.
    static func isBlockedOut(_ date: Date, universal tier: UniversalPassTier) -> Bool {
        switch tier {
        case .none:      return false
        case .premier:   return false          // no blockouts
        case .preferred: return universalDateKey(date, in: preferredDates)
        case .power:     return universalDateKey(date, in: powerDates)
        case .select:    return universalDateKey(date, in: selectDates)
        case .seasonal:  return universalDateKey(date, in: seasonalDates)
        }
    }

    // MARK: - Helpers

    private static func key(_ date: Date) -> String {
        let cal = Calendar.current
        return String(format: "%04d-%02d-%02d",
                      cal.component(.year,  from: date),
                      cal.component(.month, from: date),
                      cal.component(.day,   from: date))
    }

    private static func disneyDateKey(_ date: Date, in set: Set<String>) -> Bool {
        set.contains(key(date))
    }
    private static func universalDateKey(_ date: Date, in set: Set<String>) -> Bool {
        set.contains(key(date))
    }

    // MARK: - Disney Pixie Dust Dates

    private static let pixieDustDates: Set<String> = {
        var dates = Set<String>()
        // 2026
        add(&dates, 2026, 1, [3,4,10,11,17,18,19,24,25,31])
        add(&dates, 2026, 2, [1,7,8,14,15,16,21,22,28])
        add(&dates, 2026, 3, [1,7,8] + Array(14...22) + Array(28...31))
        add(&dates, 2026, 4, Array(1...12) + [18,19,25,26])
        add(&dates, 2026, 5, [2,3,9,10,16,17,23,24,25,30,31])
        add(&dates, 2026, 6, [6,7,13,14,20,21,27,28])
        add(&dates, 2026, 7, Array(2...6) + [11,12,18,19,25,26])
        add(&dates, 2026, 8, [1,2,8,9,15,16,22,23,29,30])
        add(&dates, 2026, 9, [5,6,7,12,13,19,20,26,27])
        add(&dates, 2026, 10, [3,4,10,11,12,17,18,24,25,31])
        add(&dates, 2026, 11, [1,7,8,14,15] + Array(20...29))
        add(&dates, 2026, 12, [5,6,12,13] + Array(18...31))
        // 2027
        add(&dates, 2027, 1, [1,2,3,9,10,16,17,18,23,24,30,31])
        add(&dates, 2027, 2, [6,7,13,14,15,20,21,27,28])
        add(&dates, 2027, 3, [6,7] + Array(13...31))
        add(&dates, 2027, 4, [1,2,3,4,10,11,17,18,24,25])
        add(&dates, 2027, 5, [1,2,8,9,15,16,22,23,29,30,31])
        add(&dates, 2027, 6, [5,6,12,13,19,20,26,27])
        return dates
    }()

    // MARK: - Disney Pirate Dates

    private static let pirateDates: Set<String> = {
        var dates = Set<String>()
        // 2026
        add(&dates, 2026, 1, [1,2,17,18,19])
        add(&dates, 2026, 2, [14,15,16])
        add(&dates, 2026, 3, Array(14...21) + [29,30,31])
        add(&dates, 2026, 4, Array(1...9))
        add(&dates, 2026, 5, [23,24,25])
        add(&dates, 2026, 7, [2,3,4,5])
        add(&dates, 2026, 9, [5,6,7])
        add(&dates, 2026, 10, [10,11,12])
        add(&dates, 2026, 11, Array(20...28))
        add(&dates, 2026, 12, Array(19...31))
        // 2027
        add(&dates, 2027, 1, [1,2,16,17,18])
        add(&dates, 2027, 2, [13,14,15])
        add(&dates, 2027, 3, Array(13...31))
        add(&dates, 2027, 4, [1])
        add(&dates, 2027, 5, [29,30,31])
        return dates
    }()

    // MARK: - Disney Sorcerer Dates

    private static let sorcererDates: Set<String> = {
        var dates = Set<String>()
        // 2026
        add(&dates, 2026, 1, [1])
        add(&dates, 2026, 11, [25,26,27,28])
        add(&dates, 2026, 12, Array(20...31))
        // 2027
        add(&dates, 2027, 1, [1])
        return dates
    }()

    // MARK: - Universal Seasonal (2-Park Seasonal) — most restrictive non-premier Disney equivalent

    /// 2-Park Seasonal: all blockout dates that affect the main parks
    private static let seasonalDates: Set<String> = {
        var dates = Set<String>()
        // 2026 — "All parks" or main-park blockouts
        add(&dates, 2026, 1, [1,2,3,4])
        add(&dates, 2026, 2, [4,7,15,21,28])
        add(&dates, 2026, 3, [7] + Array(13...22) + [28,30,31])
        add(&dates, 2026, 4, Array(1...11))
        add(&dates, 2026, 7, Array(1...31))
        add(&dates, 2026, 11, Array(23...28))
        add(&dates, 2026, 12, Array(19...31))
        // 2027
        add(&dates, 2027, 1, [1,2,3])
        add(&dates, 2027, 3, Array(15...31))
        add(&dates, 2027, 4, [1,2,3])
        add(&dates, 2027, 7, Array(1...31))
        return dates
    }()

    // MARK: - Universal Select (2-Park Power)

    private static let selectDates: Set<String> = {
        var dates = Set<String>()
        // 2026
        add(&dates, 2026, 1, [1,2,3,4])
        add(&dates, 2026, 3, [30,31])
        add(&dates, 2026, 4, Array(1...11))
        add(&dates, 2026, 12, Array(19...31))
        // 2027
        add(&dates, 2027, 1, [1,2,3])
        add(&dates, 2027, 3, Array(15...27))
        return dates
    }()

    // MARK: - Universal Power (3-Park Power)

    private static let powerDates: Set<String> = {
        var dates = Set<String>()
        // 2026 — "All parks" and "USF & IOA" only (not Volcano Bay-only)
        add(&dates, 2026, 1, [1,2,3,4])
        add(&dates, 2026, 3, [30,31])
        add(&dates, 2026, 4, Array(1...11))
        add(&dates, 2026, 12, Array(19...31))
        // 2027
        add(&dates, 2027, 1, [1,2,3])
        add(&dates, 2027, 3, Array(15...27))
        return dates
    }()

    // MARK: - Universal Preferred (3-Park Preferred)
    // Blockouts are Volcano Bay only — no main-park restrictions outside that

    private static let preferredDates: Set<String> = {
        // Preferred only blocks Volcano Bay (before 4pm in July/Aug)
        // For the purposes of "can you go to the main parks" = never blocked
        Set<String>()
    }()

    // MARK: - Date Set Builder

    private static func add(_ set: inout Set<String>, _ year: Int, _ month: Int, _ days: [Int]) {
        for day in days {
            set.insert(String(format: "%04d-%02d-%02d", year, month, day))
        }
    }
}

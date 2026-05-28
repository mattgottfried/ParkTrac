import Foundation

// MARK: - BlockOutService
// Pure enum — no state, all static functions.

enum BlockOutService {

    // MARK: - Disney

    static func isBlockedOut(_ date: Date, disney tier: DisneyPassTier) -> Bool {
        switch tier {
        case .none:      return false
        case .incredi:   return false
        case .sorcerer:  return disneyCoreDates(date)
        case .pirate:    return disneyCoreDates(date) || allSaturdaysJunAug(date)
        case .pixieDust: return disneyCoreDates(date)
                             || allSaturdaysJunAug(date)
                             || jul4Week(date)
                             || laborDayWeekend(date)
                             || mlkWeekend(date)
                             || presidentsWeekend(date)
        }
    }

    // MARK: - Universal

    static func isBlockedOut(_ date: Date, universal tier: UniversalPassTier) -> Bool {
        switch tier {
        case .none:      return false
        case .premier:   return false
        case .preferred: return christmasNYE(date)
        case .power:     return allWeekendsYearRound(date) || disneyCoreDates(date)
        case .select:    return allWeekendsYearRound(date) || disneyCoreDates(date)
                             || memorialDayWeekend(date) || jul4Week(date)
        case .seasonal:  return allWeekendsYearRound(date) || disneyCoreDates(date)
                             || memorialDayWeekend(date) || jul4Week(date)
                             || allJunAug(date)
        }
    }

    // MARK: - Shared Block-out Ranges

    /// Christmas / NYE: Dec 20 – Jan 1
    private static func christmasNYE(_ date: Date) -> Bool {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)
        if month == 12 && day >= 20 { return true }
        if month == 1  && day == 1  { return true }
        return false
    }

    /// Spring Break: Mar 8 – Apr 18
    private static func springBreak(_ date: Date) -> Bool {
        let cal   = Calendar.current
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)
        if month == 3 && day >= 8  { return true }
        if month == 4 && day <= 18 { return true }
        return false
    }

    /// Peak Summer: Jun 14 – Aug 9
    private static func peakSummer(_ date: Date) -> Bool {
        let cal   = Calendar.current
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)
        if month == 6 && day >= 14 { return true }
        if month == 7              { return true }
        if month == 8 && day <= 9  { return true }
        return false
    }

    /// Thanksgiving week: Thu–Sun of the 4th Thursday in November
    private static func thanksgivingWeekend(_ date: Date) -> Bool {
        let cal  = Calendar.current
        let year = cal.component(.year, from: date)
        // Find 4th Thursday of November
        guard let nov1 = cal.date(from: DateComponents(year: year, month: 11, day: 1)) else { return false }
        var thurCount = 0
        var cursor = nov1
        while true {
            if cal.component(.weekday, from: cursor) == 5 { // Thursday = 5
                thurCount += 1
                if thurCount == 4 { break }
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        // cursor = 4th Thursday; block Thu–Sun
        for offset in 0...3 {
            if let d = cal.date(byAdding: .day, value: offset, to: cursor),
               cal.isDate(d, inSameDayAs: date) { return true }
        }
        return false
    }

    /// Disney Sorcerer core dates: Christmas/NYE + Spring Break + Peak Summer + Thanksgiving
    private static func disneyCoreDates(_ date: Date) -> Bool {
        christmasNYE(date) || springBreak(date) || peakSummer(date) || thanksgivingWeekend(date)
    }

    /// All Saturdays in June–August
    private static func allSaturdaysJunAug(_ date: Date) -> Bool {
        let cal   = Calendar.current
        let month = cal.component(.month, from: date)
        guard month >= 6 && month <= 8 else { return false }
        return cal.component(.weekday, from: date) == 7 // Saturday = 7
    }

    /// All of June, July, August
    private static func allJunAug(_ date: Date) -> Bool {
        let month = Calendar.current.component(.month, from: date)
        return month >= 6 && month <= 8
    }

    /// Jul 4 week: Jun 28 – Jul 7
    private static func jul4Week(_ date: Date) -> Bool {
        let cal   = Calendar.current
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)
        if month == 6 && day >= 28 { return true }
        if month == 7 && day <= 7  { return true }
        return false
    }

    /// Labor Day weekend: Sat–Mon of first Mon in September
    private static func laborDayWeekend(_ date: Date) -> Bool {
        let cal  = Calendar.current
        let year = cal.component(.year, from: date)
        guard let sep1 = cal.date(from: DateComponents(year: year, month: 9, day: 1)) else { return false }
        var cursor = sep1
        while cal.component(.weekday, from: cursor) != 2 { // Monday = 2
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        // cursor = first Monday; block Sat–Mon
        for offset in [-2, -1, 0] {
            if let d = cal.date(byAdding: .day, value: offset, to: cursor),
               cal.isDate(d, inSameDayAs: date) { return true }
        }
        return false
    }

    /// MLK weekend: Sat–Mon of 3rd Monday in January
    private static func mlkWeekend(_ date: Date) -> Bool {
        let cal  = Calendar.current
        let year = cal.component(.year, from: date)
        guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return false }
        var monCount = 0
        var cursor = jan1
        while true {
            if cal.component(.weekday, from: cursor) == 2 {
                monCount += 1
                if monCount == 3 { break }
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        for offset in [-2, -1, 0] {
            if let d = cal.date(byAdding: .day, value: offset, to: cursor),
               cal.isDate(d, inSameDayAs: date) { return true }
        }
        return false
    }

    /// Presidents' weekend: Sat–Mon of 3rd Monday in February
    private static func presidentsWeekend(_ date: Date) -> Bool {
        let cal  = Calendar.current
        let year = cal.component(.year, from: date)
        guard let feb1 = cal.date(from: DateComponents(year: year, month: 2, day: 1)) else { return false }
        var monCount = 0
        var cursor = feb1
        while true {
            if cal.component(.weekday, from: cursor) == 2 {
                monCount += 1
                if monCount == 3 { break }
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        for offset in [-2, -1, 0] {
            if let d = cal.date(byAdding: .day, value: offset, to: cursor),
               cal.isDate(d, inSameDayAs: date) { return true }
        }
        return false
    }

    /// Memorial Day weekend: Sat–Mon of last Monday in May
    private static func memorialDayWeekend(_ date: Date) -> Bool {
        let cal  = Calendar.current
        let year = cal.component(.year, from: date)
        // Last Monday of May
        guard let may31 = cal.date(from: DateComponents(year: year, month: 5, day: 31)) else { return false }
        var cursor = may31
        while cal.component(.weekday, from: cursor) != 2 {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        for offset in [-2, -1, 0] {
            if let d = cal.date(byAdding: .day, value: offset, to: cursor),
               cal.isDate(d, inSameDayAs: date) { return true }
        }
        return false
    }

    /// All Saturdays and Sundays year-round
    private static func allWeekendsYearRound(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 // Sunday=1, Saturday=7
    }
}

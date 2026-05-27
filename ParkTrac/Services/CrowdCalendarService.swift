import Foundation

// MARK: - Crowd Calendar Service
// Predicts park crowd levels using hardcoded seasonal patterns.
// Based on typical WDW/Universal attendance patterns:
// Florida school calendar, major US holidays, seasonal events.

enum CrowdCalendarService {

    static func crowdLevel(for date: Date, resort: ParkGroup) -> CrowdLevel {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let month = comps.month, let day = comps.day, let weekday = comps.weekday else {
            return .moderate
        }

        var score = baseScore(weekday: weekday)
        score += seasonalScore(month: month, day: day)
        score += holidayScore(month: month, day: day, year: comps.year ?? 2026, cal: cal, date: date)
        if resort == .universal { score += universalEventScore(month: month, day: day) }

        return levelFromScore(score)
    }

    // MARK: - Scoring

    /// Weekday base: Mon-Thu quieter, Fri-Sun busier
    private static func baseScore(weekday: Int) -> Int {
        // 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
        switch weekday {
        case 1:       return 2  // Sunday
        case 6, 7:    return 2  // Friday, Saturday
        case 5:       return 1  // Thursday
        default:      return 0  // Mon–Wed quietest
        }
    }

    /// Seasonal overlays (school year patterns)
    private static func seasonalScore(month: Int, day: Int) -> Int {
        switch month {
        // Peak Summer
        case 6 where day >= 15:  return 3
        case 7:                  return 3
        case 8 where day <= 20:  return 3
        // Early June / Late August (shoulder summer)
        case 6 where day < 15:   return 2
        case 8 where day > 20:   return 2
        // Spring Break window (mid-March through mid-April)
        case 3 where day >= 8:   return 3
        case 4 where day <= 20:  return 3
        // May (end of school year, busy)
        case 5:                  return 2
        // September–early October (quieter after Labor Day)
        case 9:                  return -1
        case 10 where day <= 10: return -1
        // Mid-October through early November (Food & Wine etc.)
        case 10 where day > 10:  return 1
        case 11 where day <= 15: return 1
        // January (quiet after New Year)
        case 1 where day >= 6:
            return -1
        // February (quiet, but not Valentine's Day week)
        case 2 where day < 13 || day > 17:
            return -1
        default:
            return 0
        }
    }

    /// Major holidays and events
    private static func holidayScore(month: Int, day: Int, year: Int, cal: Calendar, date: Date) -> Int {
        // Christmas / New Year mega-season
        if month == 12 && day >= 20 { return 5 }
        if month == 1 && day <= 4 { return 5 }
        if month == 1 && day >= 5 && day <= 7 { return 2 } // NYE hangover week

        // Thanksgiving week — 4th Thursday of November
        if month == 11 {
            let thanksgivingDay = nthWeekday(5, weekday: 5, month: 11, year: year, cal: cal)
            let delta = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                           to: cal.startOfDay(for: thanksgivingDay)).day ?? 99
            if (-3...3).contains(delta) { return 4 }
        }

        // July 4th
        if month == 7 && (3...7).contains(day) { return 3 }

        // Memorial Day weekend (last Monday of May)
        if month == 5 {
            let memorialDay = lastWeekday(weekday: 2, month: 5, year: year, cal: cal)
            let delta = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                           to: cal.startOfDay(for: memorialDay)).day ?? 99
            if (-2...0).contains(delta) { return 3 }
        }

        // Labor Day weekend (first Monday of September)
        if month == 9 {
            let laborDay = nthWeekday(1, weekday: 2, month: 9, year: year, cal: cal)
            let delta = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                           to: cal.startOfDay(for: laborDay)).day ?? 99
            if (-2...0).contains(delta) { return 2 }
        }

        // Martin Luther King Jr. Weekend (3rd Monday of January)
        if month == 1 {
            let mlk = nthWeekday(3, weekday: 2, month: 1, year: year, cal: cal)
            let delta = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                           to: cal.startOfDay(for: mlk)).day ?? 99
            if (-2...0).contains(delta) { return 2 }
        }

        // Presidents' Day weekend (3rd Monday of February)
        if month == 2 {
            let presidents = nthWeekday(3, weekday: 2, month: 2, year: year, cal: cal)
            let delta = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                           to: cal.startOfDay(for: presidents)).day ?? 99
            if (-2...0).contains(delta) { return 2 }
        }

        return 0
    }

    /// Universal-specific events (HHN, Mardi Gras, etc.)
    private static func universalEventScore(month: Int, day: Int) -> Int {
        // Halloween Horror Nights (early September–early November evenings)
        if month == 9 && day >= 5 { return 1 }
        if month == 10 { return 1 }
        if month == 11 && day <= 3 { return 1 }
        // Mardi Gras (February–April, varies by year)
        if month == 2 && day >= 8 { return 1 }
        if month == 3 && day <= 10 { return 1 }
        return 0
    }

    // MARK: - Score → CrowdLevel

    private static func levelFromScore(_ score: Int) -> CrowdLevel {
        switch score {
        case ..<1:  return .ghost
        case 1:     return .low
        case 2...3: return .moderate
        case 4...5: return .high
        default:    return .veryHigh
        }
    }

    // MARK: - Calendar Helpers

    /// Returns the Nth occurrence of a weekday in the given month/year.
    /// weekday: 1=Sun, 2=Mon, … 7=Sat (Calendar.current convention)
    private static func nthWeekday(_ n: Int, weekday: Int, month: Int, year: Int, cal: Calendar) -> Date {
        let comps = DateComponents(year: year, month: month, weekday: weekday, weekdayOrdinal: n)
        return cal.date(from: comps) ?? .now
    }

    /// Returns the last occurrence of a weekday in the given month/year.
    private static func lastWeekday(weekday: Int, month: Int, year: Int, cal: Calendar) -> Date {
        let comps = DateComponents(year: year, month: month, weekday: weekday, weekdayOrdinal: -1)
        return cal.date(from: comps) ?? .now
    }

    // MARK: - Best time advice

    static func bestTimeAdvice(for level: CrowdLevel) -> String {
        switch level {
        case .ghost, .low:  return "Great day to visit — arrive any time."
        case .moderate:     return "Arrive at park open for the best experience."
        case .high:         return "Arrive 30 min before open; hit top rides first."
        case .veryHigh:     return "Very busy — pre-book Lightning Lane; arrive at park open."
        }
    }
}

import Foundation
import SwiftData

/// A closed-out annual pass period, snapshotted when you tap "I Renewed" — the cost/tier you
/// paid and the date range it covered. Only past, finished periods are stored here; the
/// *current* period is still just `AppState.disneyPassCost`/`disneyPassTier`/`disneyPassExpiry`
/// (and the Universal equivalents), with its start taken as the most recent `PassPeriod.endDate`
/// for that resort (or unbounded if there's no history yet — a new install's first pass).
@Model
final class PassPeriod {
    var resort: String = ""
    var tier: String = ""
    var cost: Double = 0
    var startDate: Date = Date()
    var endDate: Date = Date()

    init(resort: String, tier: String, cost: Double, startDate: Date, endDate: Date) {
        self.resort = resort
        self.tier = tier
        self.cost = cost
        self.startDate = startDate
        self.endDate = endDate
    }
}

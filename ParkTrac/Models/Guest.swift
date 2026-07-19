import SwiftData
import Foundation

@Model
final class Guest {
    var id: UUID = UUID()
    var name: String = ""
    var hasDisneyPass: Bool = false
    var hasUniversalPass: Bool = false
    var disneyPassTier: String = ""
    var universalPassTier: String = ""
    var isFrequent: Bool = true
    var syncUpdatedAt: Date = Date()

    init(
        name: String,
        hasDisneyPass: Bool = false,
        hasUniversalPass: Bool = false,
        disneyPassTier: String = "",
        universalPassTier: String = "",
        isFrequent: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.hasDisneyPass = hasDisneyPass
        self.hasUniversalPass = hasUniversalPass
        self.disneyPassTier = disneyPassTier
        self.universalPassTier = universalPassTier
        self.isFrequent = isFrequent
        self.syncUpdatedAt = .now
    }
}

import SwiftData
import Foundation

@Model
final class Guest {
    var name: String
    var hasDisneyPass: Bool
    var hasUniversalPass: Bool
    var disneyPassTier: String
    var universalPassTier: String
    var isFrequent: Bool

    init(
        name: String,
        hasDisneyPass: Bool = false,
        hasUniversalPass: Bool = false,
        disneyPassTier: String = "",
        universalPassTier: String = "",
        isFrequent: Bool = true
    ) {
        self.name = name
        self.hasDisneyPass = hasDisneyPass
        self.hasUniversalPass = hasUniversalPass
        self.disneyPassTier = disneyPassTier
        self.universalPassTier = universalPassTier
        self.isFrequent = isFrequent
    }
}

import SwiftUI

struct BadgeDefinition: Identifiable {
    let id: String
    let title: String
    let description: String        // what it is
    let howToEarn: String          // shown when locked
    let systemImage: String
    let color: Color
    let isEarned: ([BucketRestaurant], [HotelStay], [RideLog]) -> Bool
}

// MARK: - Standby-avoidance badge rules (pure)
// Everything a standby-wait-avoiding AP holder already does without a return-time pass — ride
// at rope drop, ride late, favor short waits, beat the posted sign — earns its own badge, built
// only from fields RideLog already has (no new schema).

enum StandbyBadgeRules {
    static let shortWaitThreshold = 15
    static let earlyBirdHour = 9
    static let nightOwlHour = 21
    static let beatTheWaitMargin = 20
    static let shortWaitStreakCount = 10

    static func isEarlyBird(rides: [(riddenAt: Date, waitMinutes: Int?)], calendar: Calendar = .current) -> Bool {
        rides.contains { ride in
            calendar.component(.hour, from: ride.riddenAt) < earlyBirdHour
                && (ride.waitMinutes ?? Int.max) <= shortWaitThreshold
        }
    }

    static func isNightOwl(rides: [Date], calendar: Calendar = .current) -> Bool {
        rides.contains { calendar.component(.hour, from: $0) >= nightOwlHour }
    }

    static func hasShortWaitStreak(waitMinutes: [Int?]) -> Bool {
        waitMinutes.filter { ($0 ?? Int.max) <= shortWaitThreshold }.count >= shortWaitStreakCount
    }

    static func hasBeatTheWait(rides: [(posted: Int?, actual: Int?)]) -> Bool {
        rides.contains { ride in
            guard let posted = ride.posted, let actual = ride.actual else { return false }
            return posted - actual >= beatTheWaitMargin
        }
    }
}

// MARK: - All Badges

let allBadges: [BadgeDefinition] = [

    // MARK: Dining — visit count
    BadgeDefinition(
        id: "first_bite",
        title: "First Bite",
        description: "Your first restaurant visit logged.",
        howToEarn: "Log your first restaurant visit.",
        systemImage: "fork.knife",
        color: .green,
        isEarned: { restaurants, _, _ in restaurants.filter(\.isVisited).count >= 1 }
    ),
    BadgeDefinition(
        id: "food_explorer",
        title: "Food Explorer",
        description: "Visited 10 restaurants.",
        howToEarn: "Visit 10 restaurants.",
        systemImage: "map.fill",
        color: .green,
        isEarned: { restaurants, _, _ in restaurants.filter(\.isVisited).count >= 10 }
    ),
    BadgeDefinition(
        id: "foodie",
        title: "Foodie",
        description: "Visited 25 restaurants.",
        howToEarn: "Visit 25 restaurants.",
        systemImage: "star.fill",
        color: .orange,
        isEarned: { restaurants, _, _ in restaurants.filter(\.isVisited).count >= 25 }
    ),
    BadgeDefinition(
        id: "culinary_master",
        title: "Culinary Master",
        description: "Visited 50 restaurants.",
        howToEarn: "Visit 50 restaurants.",
        systemImage: "crown.fill",
        color: .yellow,
        isEarned: { restaurants, _, _ in restaurants.filter(\.isVisited).count >= 50 }
    ),

    // MARK: Dining — category
    BadgeDefinition(
        id: "character_fan",
        title: "Character Fan",
        description: "Visited every Character Dining experience.",
        howToEarn: "Visit all Character Dining restaurants.",
        systemImage: "theatermasks.fill",
        color: .purple,
        isEarned: { restaurants, _, _ in
            let cd = restaurants.filter { $0.category == "Character Dining" }
            return !cd.isEmpty && cd.allSatisfy(\.isVisited)
        }
    ),
    BadgeDefinition(
        id: "table_service_pro",
        title: "Table Service Pro",
        description: "Visited 10 Table Service restaurants.",
        howToEarn: "Visit 10 Table Service restaurants.",
        systemImage: "tablecells.fill",
        color: .blue,
        isEarned: { restaurants, _, _ in
            restaurants.filter { $0.category == "Table Service" && $0.isVisited }.count >= 10
        }
    ),
    BadgeDefinition(
        id: "quick_bites",
        title: "Quick Bites",
        description: "Visited 10 Quick Service spots.",
        howToEarn: "Visit 10 Quick Service restaurants.",
        systemImage: "bolt.fill",
        color: .yellow,
        isEarned: { restaurants, _, _ in
            restaurants.filter { $0.category == "Quick Service" && $0.isVisited }.count >= 10
        }
    ),

    // MARK: Dining — location
    BadgeDefinition(
        id: "epcot_world_tour",
        title: "World Tour",
        description: "Visited 5 EPCOT restaurants.",
        howToEarn: "Visit 5 restaurants in EPCOT.",
        systemImage: "globe.americas.fill",
        color: .cyan,
        isEarned: { restaurants, _, _ in
            restaurants.filter { $0.park == "EPCOT" && $0.isVisited }.count >= 5
        }
    ),
    BadgeDefinition(
        id: "springs_regular",
        title: "Springs Regular",
        description: "Visited 5 Disney Springs restaurants.",
        howToEarn: "Visit 5 restaurants at Disney Springs.",
        systemImage: "building.2.fill",
        color: .teal,
        isEarned: { restaurants, _, _ in
            restaurants.filter { $0.park == "Disney Springs" && $0.isVisited }.count >= 5
        }
    ),

    // MARK: Dining — ratings
    BadgeDefinition(
        id: "high_standards",
        title: "High Standards",
        description: "Gave a perfect 5-star average rating to 5 restaurants.",
        howToEarn: "Rate 5 restaurants with an average of 5 stars.",
        systemImage: "star.circle.fill",
        color: .yellow,
        isEarned: { restaurants, _, _ in
            restaurants.filter { ($0.averageRating ?? 0) >= 5.0 }.count >= 5
        }
    ),

    // MARK: Hotels — stay count
    BadgeDefinition(
        id: "first_stay",
        title: "First Stay",
        description: "Your first resort hotel stay logged.",
        howToEarn: "Log your first hotel stay.",
        systemImage: "house.fill",
        color: .blue,
        isEarned: { _, hotels, _ in hotels.filter(\.isVisited).count >= 1 }
    ),
    BadgeDefinition(
        id: "resort_hopper",
        title: "Resort Hopper",
        description: "Stayed at 3 different resort hotels.",
        howToEarn: "Stay at 3 different hotels.",
        systemImage: "suitcase.fill",
        color: .indigo,
        isEarned: { _, hotels, _ in hotels.filter(\.isVisited).count >= 3 }
    ),
    BadgeDefinition(
        id: "hotel_connoisseur",
        title: "Hotel Connoisseur",
        description: "Stayed at 5 different resort hotels.",
        howToEarn: "Stay at 5 different hotels.",
        systemImage: "building.columns.fill",
        color: .purple,
        isEarned: { _, hotels, _ in hotels.filter(\.isVisited).count >= 5 }
    ),

    // MARK: Hotels — tier
    BadgeDefinition(
        id: "deluxe_taste",
        title: "Deluxe Taste",
        description: "Stayed at a Disney Deluxe resort.",
        howToEarn: "Stay at any Disney Deluxe resort.",
        systemImage: "sparkles",
        color: .yellow,
        isEarned: { _, hotels, _ in hotels.contains { $0.tier == "Deluxe" && $0.isVisited } }
    ),
    BadgeDefinition(
        id: "value_savvy",
        title: "Value Savvy",
        description: "Stayed at a Value resort.",
        howToEarn: "Stay at any Value resort.",
        systemImage: "dollarsign.circle.fill",
        color: .green,
        isEarned: { _, hotels, _ in hotels.contains { $0.tier == "Value" && $0.isVisited } }
    ),
    BadgeDefinition(
        id: "universal_vip",
        title: "Universal VIP",
        description: "Stayed at a Universal Premier hotel.",
        howToEarn: "Stay at a Universal Premier hotel (Portofino Bay, Hard Rock, or Royal Pacific).",
        systemImage: "camera.fill",
        color: .orange,
        isEarned: { _, hotels, _ in
            hotels.contains { $0.resort == "Universal Orlando" && $0.tier == "Premier" && $0.isVisited }
        }
    ),

    // MARK: Cross-resort
    BadgeDefinition(
        id: "bicoastal",
        title: "Bicoastal",
        description: "Visited restaurants at both Walt Disney World and Universal Orlando.",
        howToEarn: "Visit at least one restaurant at each resort.",
        systemImage: "arrow.left.arrow.right",
        color: .mint,
        isEarned: { restaurants, _, _ in
            let visited: [BucketRestaurant] = restaurants.filter(\.isVisited)
            let resorts: Set<String> = Set(visited.map(\.resort))
            return resorts.contains("Walt Disney World") && resorts.contains("Universal Orlando")
        }
    ),
    BadgeDefinition(
        id: "frequent_visitor",
        title: "Frequent Visitor",
        description: "Stayed at 3 Universal hotels AND 3 Disney hotels.",
        howToEarn: "Stay at 3 Universal and 3 Disney hotels.",
        systemImage: "figure.walk.motion",
        color: .cyan,
        isEarned: { _, hotels, _ in
            let visited  = hotels.filter(\.isVisited)
            let disney   = visited.filter { $0.resort == "Walt Disney World" }.count
            let universal = visited.filter { $0.resort == "Universal Orlando" }.count
            return disney >= 3 && universal >= 3
        }
    ),

    // MARK: Ride Log badges
    BadgeDefinition(
        id: "first_ride_log",
        title: "First Ride",
        description: "Logged your first ride with Rode It!",
        howToEarn: "Tap \u{201C}Rode It!\u{201D} on any attraction.",
        systemImage: "ticket.fill",
        color: .green,
        isEarned: { _, _, rides in !rides.isEmpty }
    ),
    BadgeDefinition(
        id: "century_rider",
        title: "Century Rider",
        description: "Logged 100 total rides.",
        howToEarn: "Log 100 rides with Rode It!",
        systemImage: "100.circle.fill",
        color: .orange,
        isEarned: { _, _, rides in rides.count >= 100 }
    ),
    BadgeDefinition(
        id: "ride_repeat",
        title: "Repeat Rider",
        description: "Rode the same attraction 10 times.",
        howToEarn: "Ride any single attraction 10 or more times.",
        systemImage: "arrow.clockwise.circle.fill",
        color: .purple,
        isEarned: { _, _, rides in
            var counts: [String: Int] = [:]
            for log in rides { counts[log.rideId, default: 0] += 1 }
            return counts.values.contains { $0 >= 10 }
        }
    ),

    // MARK: Standby-avoidance badges
    BadgeDefinition(
        id: "early_bird",
        title: "Early Bird",
        description: "Rode something short before 9 AM.",
        howToEarn: "Log a ride with Rode It! before 9 AM with a 15 min or shorter wait \u{2014} classic rope drop timing.",
        systemImage: "sunrise.fill",
        color: .orange,
        isEarned: { _, _, rides in
            StandbyBadgeRules.isEarlyBird(rides: rides.map { (riddenAt: $0.riddenAt, waitMinutes: $0.waitMinutes) })
        }
    ),
    BadgeDefinition(
        id: "night_owl",
        title: "Night Owl",
        description: "Rode something after 9 PM.",
        howToEarn: "Log a ride with Rode It! at 9 PM or later.",
        systemImage: "moon.stars.fill",
        color: .indigo,
        isEarned: { _, _, rides in StandbyBadgeRules.isNightOwl(rides: rides.map(\.riddenAt)) }
    ),
    BadgeDefinition(
        id: "short_wait_streak",
        title: "Short Wait Streak",
        description: "Logged 10 rides with a 15 min or shorter wait.",
        howToEarn: "Log 10 rides with Rode It! where the wait was 15 minutes or less.",
        systemImage: "bolt.fill",
        color: .green,
        isEarned: { _, _, rides in StandbyBadgeRules.hasShortWaitStreak(waitMinutes: rides.map(\.waitMinutes)) }
    ),
    BadgeDefinition(
        id: "beat_the_wait",
        title: "Beat the Wait",
        description: "Timed a ride that beat its posted wait by 20+ minutes.",
        howToEarn: "Use the wait stopwatch on a ride where your actual wait came in 20+ minutes under the posted sign.",
        systemImage: "stopwatch.fill",
        color: .teal,
        isEarned: { _, _, rides in
            StandbyBadgeRules.hasBeatTheWait(rides: rides.map { (posted: $0.waitMinutes, actual: $0.actualWaitMinutes) })
        }
    ),
]

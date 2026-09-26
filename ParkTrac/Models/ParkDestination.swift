import Foundation
import SwiftUI
import MapKit

/// A resort the app covers. Raw values are persisted in SwiftData (`PlanItem.resort`,
/// `RideLog.resort`, …) and iCloud KVS — never rename an existing one.
enum ParkGroup: String, CaseIterable, Identifiable {
    case disney = "Walt Disney World"
    case universal = "Universal Orlando"
    case tokyoDisney = "Tokyo Disney Resort"
    case universalJapan = "Universal Studios Japan"

    var id: String { rawValue }

    enum Brand { case disney, universal }

    var brand: Brand {
        switch self {
        case .disney, .tokyoDisney:        return .disney
        case .universal, .universalJapan:  return .universal
        }
    }

    var isDisneyBrand: Bool { brand == .disney }
    /// Orlando-only features: ticket prices, annual passes / blockouts, US crowd calendar,
    /// seeded restaurants & hotels, AP discounts, Lightning Lane / DAS / AAP.
    var isOrlando: Bool { self == .disney || self == .universal }

    static let orlando: [ParkGroup] = [.disney, .universal]

    /// Short name for tight spaces (resort cards, pickers)
    var shortName: String {
        switch self {
        case .disney:         return "Disney World"
        case .universal:      return "Universal Orlando"
        case .tokyoDisney:    return "Tokyo Disney"
        case .universalJapan: return "Universal Japan"
        }
    }

    var systemImage: String {
        switch self {
        case .disney, .tokyoDisney:  return "crown.fill"
        case .universal:             return "globe.americas.fill"
        case .universalJapan:        return "globe.asia.australia.fill"
        }
    }

    var timeZone: TimeZone {
        isOrlando ? TimeZone(identifier: "America/New_York")! : TimeZone(identifier: "Asia/Tokyo")!
    }

    var currencyCode: String { isOrlando ? "USD" : "JPY" }

    /// themeparks.wiki destination UUID, when known. Japan resorts are resolved at runtime
    /// from `/destinations` by `apiSlug` (see ParkAPIService.fetchParks(for:)).
    var destinationId: String? {
        switch self {
        case .disney:    return "e957da41-3552-4cf6-b636-5babc5cbc4e5"
        case .universal: return "89db5d43-c434-4097-b71f-f6869f495a22"
        case .tokyoDisney, .universalJapan: return nil
        }
    }

    /// themeparks.wiki destination slug
    var apiSlug: String {
        switch self {
        case .disney:         return "waltdisneyworldresort"
        case .universal:      return "universalorlando"
        case .tokyoDisney:    return "tokyodisneyresort"
        case .universalJapan: return "universalstudiosjapan"
        }
    }

    /// Words that identify the destination by name if the slug ever changes
    var apiNameKeywords: [String] {
        switch self {
        case .disney:         return ["walt disney world"]
        case .universal:      return ["universal orlando"]
        case .tokyoDisney:    return ["tokyo disney"]
        case .universalJapan: return ["universal studios japan"]
        }
    }

    /// What the paid / free return-time queues are called at this resort
    /// (themeparks.wiki PAID_RETURN_TIME / RETURN_TIME).
    var returnPassNames: (free: String, paid: String, section: String, short: String) {
        switch self {
        case .tokyoDisney:
            return ("Priority Pass", "Premier Access", "Priority Pass & Premier Access", "PP")
        case .universalJapan:
            return ("Express", "Express Pass", "Express Pass", "EX")
        case .disney, .universal:
            return ("Multi Pass", "Single Pass", "Lightning Lane", "LL")
        }
    }

    var defaultCoordinate: CLLocationCoordinate2D {
        switch self {
        case .disney:    return CLLocationCoordinate2D(latitude: 28.3852, longitude: -81.5639)
        case .universal: return CLLocationCoordinate2D(latitude: 28.4756, longitude: -81.4672)
        // Between Tokyo Disneyland and Tokyo DisneySea
        case .tokyoDisney:    return CLLocationCoordinate2D(latitude: 35.6300, longitude: 139.8830)
        case .universalJapan: return CLLocationCoordinate2D(latitude: 34.6654, longitude: 135.4323)
        }
    }

    var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: defaultCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07))
    }

    var theme: ParkTheme {
        switch self {
        case .disney:
            return ParkTheme(
                primaryColor: Color(red: 0/255, green: 60/255, blue: 113/255),
                accentColor: Color(red: 253/255, green: 185/255, blue: 19/255),
                annotationTextColor: .white,
                cardBackground: Color(.systemBackground),
                cardShadowOpacity: 0.08,
                preferredColorScheme: .light,
                tabBarTint: Color(red: 0/255, green: 60/255, blue: 113/255)
            )
        case .universal:
            return ParkTheme(
                primaryColor: Color(red: 20/255, green: 20/255, blue: 20/255),
                accentColor: Color(red: 252/255, green: 190/255, blue: 17/255),
                annotationTextColor: .white,
                cardBackground: Color(.secondarySystemGroupedBackground),
                cardShadowOpacity: 0.0,
                preferredColorScheme: .dark,
                tabBarTint: Color(red: 252/255, green: 190/255, blue: 17/255)
            )
        case .tokyoDisney:
            // Sky blue + soft pink
            return ParkTheme(
                primaryColor: Color(red: 0/255, green: 112/255, blue: 187/255),
                accentColor: Color(red: 236/255, green: 112/255, blue: 160/255),
                annotationTextColor: .white,
                cardBackground: Color(.systemBackground),
                cardShadowOpacity: 0.08,
                preferredColorScheme: .light,
                tabBarTint: Color(red: 0/255, green: 112/255, blue: 187/255)
            )
        case .universalJapan:
            // Universal blue + gold
            return ParkTheme(
                primaryColor: Color(red: 0/255, green: 56/255, blue: 147/255),
                accentColor: Color(red: 252/255, green: 190/255, blue: 17/255),
                annotationTextColor: .white,
                cardBackground: Color(.secondarySystemGroupedBackground),
                cardShadowOpacity: 0.0,
                preferredColorScheme: .dark,
                tabBarTint: Color(red: 252/255, green: 190/255, blue: 17/255)
            )
        }
    }
}

struct ParkTheme {
    let primaryColor: Color
    let accentColor: Color
    let annotationTextColor: Color
    let cardBackground: Color
    let cardShadowOpacity: Double
    let preferredColorScheme: ColorScheme
    let tabBarTint: Color
}

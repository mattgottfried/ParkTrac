import Foundation
import SwiftUI
import MapKit

enum ParkGroup: String, CaseIterable, Identifiable {
    case disney = "Walt Disney World"
    case universal = "Universal Orlando"

    var id: String { rawValue }

    var destinationId: String {
        switch self {
        case .disney:    return "e957da41-3552-4cf6-b636-5babc5cbc4e5"
        case .universal: return "89db5d43-c434-4097-b71f-f6869f495a22"
        }
    }

    var defaultCoordinate: CLLocationCoordinate2D {
        switch self {
        case .disney:    return CLLocationCoordinate2D(latitude: 28.3852, longitude: -81.5639)
        case .universal: return CLLocationCoordinate2D(latitude: 28.4756, longitude: -81.4672)
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

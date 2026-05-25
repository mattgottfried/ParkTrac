import Foundation
import SwiftUI

enum ParkGroup: String, CaseIterable, Identifiable {
    case disney = "Walt Disney World"
    case universal = "Universal Orlando"

    var id: String { rawValue }

    var destinationId: String {
        switch self {
        case .disney:    return "e957da41-3552-4cf6-b636-5babc5cbc4e6"
        case .universal: return "eb3f4560-2383-4a36-9152-6b3e5ed6bc57"
        }
    }

    var theme: ParkTheme {
        switch self {
        case .disney:
            return ParkTheme(
                primaryColor: Color(red: 0/255, green: 60/255, blue: 113/255),
                accentColor: Color(red: 253/255, green: 185/255, blue: 19/255),
                annotationTextColor: .white
            )
        case .universal:
            return ParkTheme(
                primaryColor: Color(red: 20/255, green: 20/255, blue: 20/255),
                accentColor: Color(red: 252/255, green: 190/255, blue: 17/255),
                annotationTextColor: .black
            )
        }
    }
}

struct ParkTheme {
    let primaryColor: Color
    let accentColor: Color
    let annotationTextColor: Color
}

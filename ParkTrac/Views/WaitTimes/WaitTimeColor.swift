import SwiftUI

/// Shared wait-time badge color used by both RideCardView and WaitTimeAnnotation.
/// Centralising the thresholds ensures both surfaces stay in sync.
func waitTimeColor(minutes: Int?, isOperating: Bool, status: String?) -> Color {
    if status == "DOWN" { return Color(red: 1, green: 0.55, blue: 0) }
    guard isOperating else { return .gray }
    guard let m = minutes else { return .blue }
    if m < 30 { return .green }
    if m < 60 { return Color(red: 1, green: 0.75, blue: 0) }
    return .red
}

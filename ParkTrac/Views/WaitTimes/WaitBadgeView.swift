import SwiftUI

struct WaitBadgeView: View {
    let entry: LiveDataEntry

    private var badgeColor: Color {
        guard entry.isOperating else { return .gray }
        guard let minutes = entry.waitMinutes else { return .blue }
        if minutes < 30 { return .green }
        if minutes < 60 { return .yellow }
        return .red
    }

    private var label: String {
        guard entry.isOperating else { return entry.statusDisplay }
        guard let minutes = entry.waitMinutes else { return "—" }
        return "\(minutes) min"
    }

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(badgeColor, lineWidth: 1))
    }
}

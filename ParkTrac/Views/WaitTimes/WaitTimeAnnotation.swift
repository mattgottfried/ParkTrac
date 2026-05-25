import SwiftUI

struct WaitTimeAnnotation: View {
    let ride: DisplayRide
    let theme: ParkTheme
    @Binding var selectedRide: DisplayRide?

    private var badgeColor: Color {
        guard ride.isOperating else { return .gray }
        guard let minutes = ride.waitMinutes else { return .blue }
        if minutes < 30 { return .green }
        if minutes < 60 { return Color(red: 1, green: 0.75, blue: 0) }
        return .red
    }

    private var label: String {
        guard ride.isOperating else { return "✕" }
        guard let minutes = ride.waitMinutes else { return "—" }
        return "\(minutes)"
    }

    var body: some View {
        Button {
            selectedRide = ride
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 36, height: 36)
                        .shadow(radius: 2)
                    VStack(spacing: 0) {
                        Text(label)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if ride.isOperating && ride.waitMinutes != nil {
                            Text("min")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                // Small triangle pointer
                Triangle()
                    .fill(badgeColor)
                    .frame(width: 8, height: 5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

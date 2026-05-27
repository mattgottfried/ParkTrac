import SwiftUI

struct WaitTimeAnnotation: View {
    let ride: DisplayRide
    let theme: ParkTheme
    @Binding var selectedRide: DisplayRide?

    private var badgeColor: Color {
        waitTimeColor(minutes: ride.waitMinutes, isOperating: ride.isOperating, status: ride.status)
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

                    annotationContent
                }
                // Small triangle pointer
                Triangle()
                    .fill(badgeColor)
                    .frame(width: 8, height: 5)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var annotationContent: some View {
        if ride.status == "DOWN" {
            Image(systemName: "exclamationmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        } else if !ride.isOperating {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        } else if let minutes = ride.waitMinutes {
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("min")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        } else {
            Text("—")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
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

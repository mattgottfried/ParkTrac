import SwiftUI

struct RideCardView: View {
    let ride: DisplayRide
    let theme: ParkTheme

    private var badgeColor: Color {
        waitTimeColor(minutes: ride.waitMinutes, isOperating: ride.isOperating, status: ride.status)
    }

    private var meta: RideInfo? { rideMetadata[ride.name] }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left accent strip
            Rectangle()
                .fill(badgeColor)
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ride.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ride.isOperating ? .primary : .secondary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(ride.statusDisplay)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let info = meta {
                            Circle()
                                .fill(info.thrill.color)
                                .frame(width: 6, height: 6)
                            if let h = info.heightInches {
                                Text("\(h)\"")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer()
                if ride.isOperating, let minutes = ride.waitMinutes {
                    VStack(spacing: 0) {
                        Text("\(minutes)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeColor)
                        Text("min")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(badgeColor.opacity(0.8))
                    }
                } else if ride.status == "DOWN" {
                    statusBadge(icon: "exclamationmark.triangle.fill", label: "Down", color: .orange)
                } else if !ride.isOperating {
                    statusBadge(icon: "xmark.circle.fill", label: ride.statusDisplay, color: .red)
                } else {
                    Text("—")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(theme.cardShadowOpacity), radius: 6, x: 0, y: 2)
        // Down rides stay prominent so the caution state is noticed; closed dims
        .opacity(ride.isOperating || ride.status == "DOWN" ? 1.0 : 0.6)
    }

    private func statusBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.bold())
            Text(label)
                .font(.caption.bold())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.13))
        .clipShape(Capsule())
    }
}

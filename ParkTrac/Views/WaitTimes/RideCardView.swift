import SwiftUI

struct RideCardView: View {
    let ride: DisplayRide
    let theme: ParkTheme
    /// Estimated walk from the user's location (nil when location is off or they're not in the park)
    var walkMinutes: Int? = nil
    /// Return-pass naming for this resort ("LL" / "Lightning Lane", "PP" / "Priority Pass")
    var returnPassShort: String = "LL"
    var returnPassName: String = "Lightning Lane"
    /// Picks the resort's metadata table and height unit (cm in Japan)
    var resort: ParkGroup = .disney
    /// Wait well below this ride's usual (GoodTimeService)
    var goodTime: GoodTimeToRide.Deal? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Big wait number keeps its rounded look but grows with Dynamic Type.
    @ScaledMetric(relativeTo: .title2) private var waitNumberSize: CGFloat = 28

    private var badgeColor: Color {
        waitTimeColor(minutes: ride.waitMinutes, isOperating: ride.isOperating, status: ride.status)
    }

    private var meta: RideInfo? { RideMetadata.info(for: ride.name, resort: resort) }
    private var metric: Bool { RideMetadata.prefersMetric(resort) }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left accent strip
            Rectangle()
                .fill(badgeColor)
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12))

            // At accessibility text sizes the wait moves under the name instead of beside it
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ride.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ride.isOperating ? .primary : .secondary)
                        .lineLimit(2)
                    if let goodTime {
                        Label("Good time · \(goodTime.shortText)", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green, in: Capsule())
                    }
                    HStack(spacing: 6) {
                        Text(ride.statusDisplay)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if ride.isOperating, let ll = ride.multiPass {
                            Text(ll.shortText(prefix: returnPassShort))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ll.isAvailable ? Color.orange : Color.secondary)
                        }
                        if let walk = walkMinutes {
                            Label("\(walk) min", systemImage: "figure.walk")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if LightningLaneWatchService.shared.watch(for: ride.id) != nil {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if let info = meta {
                            Circle()
                                .fill(info.thrill.color)
                                .frame(width: 6, height: 6)
                            if let h = HeightFormat.short(info, metric: metric) {
                                Text(h)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                if ride.isOperating, let minutes = ride.waitMinutes {
                    VStack(spacing: 0) {
                        Text("\(minutes)")
                            .font(.system(size: waitNumberSize, weight: .bold, design: .rounded))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ride.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows wait predictions and details")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        var parts = [ride.spokenStatus]
        if ride.isOperating, let ll = ride.multiPass {
            if ll.isAvailable, let start = ll.returnStart {
                parts.append("\(returnPassName) return \(start.formatted(date: .omitted, time: .shortened))")
            } else {
                parts.append(ll.shortText(prefix: returnPassName))
            }
        }
        if LightningLaneWatchService.shared.watch(for: ride.id) != nil {
            parts.append("watching for \(returnPassName) openings")
        }
        if let goodTime { parts.append("good time to ride, \(goodTime.longText)") }
        if let walk = walkMinutes { parts.append("about \(walk) minute walk") }
        if let meta, let h = HeightFormat.spoken(meta, metric: metric) { parts.append("height requirement \(h)") }
        return parts.joined(separator: ", ")
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

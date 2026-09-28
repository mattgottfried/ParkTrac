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
    /// This ride's usual wait at this time (GoodTimeService) — used only for the "+15 vs usual"
    /// line when it isn't already a Good Time deal (that line says the same thing better).
    var usual: GoodTimeToRide.Usual? = nil
    /// Rising/falling vs. the last refresh — a small corner arrow on the wait tile
    var trend: WaitTrend? = nil

    /// Starred as a Must-Do (shown as a star beside the name)
    var isMustDo: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The wait tile keeps its rounded look but grows with Dynamic Type.
    @ScaledMetric(relativeTo: .title2) private var waitNumberSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var tileSize: CGFloat = 58

    private var badgeColor: Color {
        waitTimeColor(minutes: ride.waitMinutes, isOperating: ride.isOperating, status: ride.status)
    }

    private var meta: RideInfo? { RideMetadata.info(for: ride.name, resort: resort) }
    private var metric: Bool { RideMetadata.prefersMetric(resort) }
    private var isDown: Bool { ride.status == "DOWN" }
    private var isWatchingLL: Bool { LightningLaneWatchService.shared.watch(for: ride.id) != nil }

    var body: some View {
        // At accessibility text sizes the tile sits above the text instead of beside it
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            waitTile

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ride.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ride.isOperating ? .primary : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isMustDo {
                        Image(systemName: "star.fill")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                    }
                }

                if let subtitle {
                    Label(subtitle.text, systemImage: subtitle.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(subtitle.color)
                        .lineLimit(1)
                }

                if hasDetails {
                    detailRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if goodTime != nil {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.6), lineWidth: 1.5)
            }
        }
        .shadow(color: .black.opacity(theme.cardShadowOpacity), radius: 6, x: 0, y: 2)
        // Down rides stay prominent so the caution state is noticed; closed dims
        .opacity(ride.isOperating || isDown ? 1.0 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ride.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows wait predictions and details")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Wait tile

    private var waitTile: some View {
        WaitTile(ride: ride, size: tileSize, numberSize: waitNumberSize, trend: trend)
    }

    // MARK: Subtitle + details

    /// One line under the name: a good-time deal, or why the ride isn't running.
    private var subtitle: (text: String, icon: String, color: Color)? {
        if let goodTime {
            return (text: "Good time · \(goodTime.shortText)", icon: "arrow.down.circle.fill", color: .green)
        }
        if isDown { return (text: "Temporarily down", icon: "wrench.and.screwdriver", color: .orange) }
        if ride.status == "UNKNOWN" { return (text: "No signal — wait time unknown", icon: "wifi.slash", color: .secondary) }
        if !ride.isOperating { return (text: ride.statusDisplay, icon: "moon.zzz", color: .secondary) }
        if let delta = usualDelta {
            let sign = delta > 0 ? "+" : ""
            return (text: "\(sign)\(delta) vs usual", icon: delta > 0 ? "arrow.up" : "arrow.down",
                    color: delta > 0 ? .orange : .green)
        }
        return nil
    }

    /// Only shown when it's a meaningful gap — a couple minutes either way isn't worth a line.
    private var usualDelta: Int? {
        guard ride.isOperating, let wait = ride.waitMinutes, let usual else { return nil }
        let delta = wait - usual.minutes
        return abs(delta) >= 10 ? delta : nil
    }

    private var hasSingleRider: Bool {
        ride.isOperating && RideMetadata.hasSingleRider(name: ride.name, resort: resort)
    }

    private var hasDetails: Bool {
        (ride.isOperating && ride.multiPass != nil) || isWatchingLL || walkMinutes != nil
            || meta != nil || hasSingleRider
    }

    /// Return pass, walk and height on one line, dot-separated.
    private var detailRow: some View {
        HStack(spacing: 6) {
            if hasSingleRider {
                Label("Single Rider", systemImage: "person.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }
            if ride.isOperating, let ll = ride.multiPass {
                Text(ll.shortText(prefix: returnPassShort))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ll.isAvailable ? Color.white : Color.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(ll.isAvailable ? Color.orange : Color.secondary.opacity(0.15), in: Capsule())
            }
            if isWatchingLL {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let walk = walkMinutes {
                Label("\(walk) min", systemImage: "figure.walk")
                    .labelStyle(.titleAndIcon)
            }
            if let info = meta {
                if walkMinutes != nil { Text("·") }
                // Thrill-level dot, then the height requirement when there is one
                HStack(spacing: 4) {
                    Circle()
                        .fill(info.thrill.color)
                        .frame(width: 6, height: 6)
                    if let h = HeightFormat.short(info, metric: metric) {
                        Text(h)
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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
}

/// The colored wait square shared by the ride card and the ride sheet: the wait (colored by
/// length), or Down / Closed / Open when there's no number.
struct WaitTile: View {
    let ride: DisplayRide
    var size: CGFloat = 58
    var numberSize: CGFloat = 24
    /// Under the number: "min" on cards, "min wait" on the ride sheet
    var unit: String = "min"
    /// Rising/falling since the last refresh — a small corner arrow, nil shows nothing
    var trend: WaitTrend? = nil

    private var isDown: Bool { ride.status == "DOWN" }

    private var isUnknown: Bool { ride.status == "UNKNOWN" }

    var color: Color {
        if isDown { return .orange }
        if isUnknown { return .gray }
        if !ride.isOperating { return .red }
        guard ride.waitMinutes != nil else { return .gray }
        return waitTimeColor(minutes: ride.waitMinutes, isOperating: ride.isOperating, status: ride.status)
    }

    var body: some View {
        VStack(spacing: 0) {
            if ride.isOperating, let minutes = ride.waitMinutes {
                Text("\(minutes)")
                    .font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.8)
            } else if isDown {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: numberSize * 0.8))
                Text("Down")
                    .font(.caption2.weight(.bold))
            } else if isUnknown {
                Image(systemName: "wifi.slash")
                    .font(.system(size: numberSize * 0.8))
                Text("No Signal")
                    .font(.caption2.weight(.bold))
            } else if !ride.isOperating {
                Image(systemName: "xmark")
                    .font(.system(size: numberSize * 0.8, weight: .bold))
                Text(ride.status == "REFURBISHMENT" ? "Refurb" : "Closed")
                    .font(.caption2.weight(.bold))
            } else {
                Text("Open")
                    .font(.subheadline.weight(.bold))
            }
        }
        .lineLimit(1)
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.21, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let trend, ride.isOperating, ride.waitMinutes != nil {
                Image(systemName: trend == .rising ? "arrow.up" : "arrow.down")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(trend == .rising ? Color.orange : Color.green, in: Circle())
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rising/falling since the last refresh — momentum only, no history required (contrast
/// `GoodTimeToRide.Usual`, which compares to a longer-run typical wait).
enum WaitTrend {
    case rising, falling

    /// nil with no prior reading, or a change under `threshold` (refresh noise, not a real trend).
    static func compute(previous: Int?, current: Int, threshold: Int = 5) -> WaitTrend? {
        guard let previous else { return nil }
        let delta = current - previous
        if delta >= threshold { return .rising }
        if delta <= -threshold { return .falling }
        return nil
    }
}

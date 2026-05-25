import SwiftUI

struct RideCardView: View {
    let ride: DisplayRide
    let theme: ParkTheme

    private var badgeColor: Color {
        guard ride.isOperating else { return .gray }
        guard let minutes = ride.waitMinutes else { return .blue }
        if minutes < 30 { return .green }
        if minutes < 60 { return Color(red: 1, green: 0.75, blue: 0) }
        return .red
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ride.isOperating ? .primary : .secondary)
                    .lineLimit(2)
                Text(ride.statusDisplay)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            } else {
                Text(ride.isOperating ? "—" : ride.statusDisplay)
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(ride.isOperating ? 1.0 : 0.6)
    }
}

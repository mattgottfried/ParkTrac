import SwiftUI

struct RideDetailSheet: View {
    let ride: DisplayRide
    let theme: ParkTheme
    let parkGroup: ParkGroup
    @Environment(\.dismiss) private var dismiss

    private var badgeColor: Color {
        guard ride.isOperating else { return .gray }
        guard let minutes = ride.waitMinutes else { return .blue }
        if minutes < 30 { return .green }
        if minutes < 60 { return Color(red: 1, green: 0.75, blue: 0) }
        return .red
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Capsule()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)

                // Ride name + status
                VStack(spacing: 6) {
                    Text(ride.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(ride.statusDisplay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Wait time display
                if ride.isOperating, let minutes = ride.waitMinutes {
                    VStack(spacing: 2) {
                        Text("\(minutes)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeColor)
                        Text("minute wait")
                            .font(.headline)
                            .foregroundStyle(badgeColor.opacity(0.8))
                    }
                } else {
                    Image(systemName: ride.status == "DOWN"
                          ? "exclamationmark.triangle.fill"
                          : "xmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(ride.status == "DOWN" ? .orange : .gray)
                }

                Divider()

                // Predictions / closure info
                RidePredictionView(ride: ride, parkGroup: parkGroup)
                    .padding(.horizontal)

                Button("Dismiss") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentColor)
                    .padding(.top, 4)
            }
            .padding()
        }
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.hidden)
    }
}

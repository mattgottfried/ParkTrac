import SwiftUI

struct RideDetailSheet: View {
    let ride: DisplayRide
    let theme: ParkTheme
    let parkGroup: ParkGroup
    var parkName: String = ""
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

                // Ride info (height, thrill, type)
                if let info = rideMetadata[ride.name] {
                    rideInfoSection(info)
                        .padding(.horizontal)
                    Divider()
                }

                // Predictions / closure info
                RidePredictionView(ride: ride, parkGroup: parkGroup, parkName: parkName)
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

    // MARK: - Ride Info Section

    @ViewBuilder
    private func rideInfoSection(_ info: RideInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ride Info")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                // Height requirement
                infoChip(
                    label: info.heightInches.map { "\($0)\" min height" } ?? "No height requirement",
                    systemImage: "ruler",
                    color: info.heightInches != nil ? .blue : .secondary
                )

                // Thrill level
                infoChip(
                    label: info.thrill.rawValue,
                    systemImage: info.thrill.systemImage,
                    color: info.thrill.color
                )
            }

            HStack(spacing: 10) {
                // Ride type
                infoChip(
                    label: info.type.rawValue,
                    systemImage: info.type.systemImage,
                    color: .indigo
                )

                // Lightning Lane
                infoChip(
                    label: info.lightningLane ? "Lightning Lane" : "Standby Only",
                    systemImage: info.lightningLane ? "bolt.fill" : "person.2.fill",
                    color: info.lightningLane ? .yellow : .secondary
                )
            }
        }
    }

    private func infoChip(label: String, systemImage: String, color: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
    }
}

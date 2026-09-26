import SwiftUI

struct HeightCheckerView: View {
    @Environment(AppState.self) private var appState

    /// Child's height, stored in cm so switching units never drifts.
    @AppStorage("heightCheckerCm") private var heightCm: Double = 48 * 2.54
    /// Empty until the user picks: follows the resort (cm in Japan, inches in Orlando).
    @AppStorage("heightCheckerMetric") private var metricChoice: String = ""
    @State private var resort: ParkGroup = .disney

    private var useCm: Bool {
        metricChoice.isEmpty ? RideMetadata.prefersMetric(resort) : metricChoice == "cm"
    }

    private var useCmBinding: Binding<Bool> {
        Binding(get: { useCm }, set: { newValue in
            metricChoice = newValue ? "cm" : "in"
            // Snap to a whole unit so the stepper shows round numbers
            heightCm = newValue ? heightCm.rounded() : (heightCm / 2.54).rounded() * 2.54
        })
    }

    /// Orlando shares one table, so the picker offers Orlando / Tokyo / USJ.
    private static let choices: [ParkGroup] = [.disney, .tokyoDisney, .universalJapan]

    private func label(for group: ParkGroup) -> String {
        switch group {
        case .universalJapan: return "USJ"
        default:              return group.isOrlando ? "Orlando" : group.shortName
        }
    }

    private var rides: [(name: String, info: RideInfo)] {
        RideMetadata.catalog(for: resort)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private var eligibleRides: [(name: String, info: RideInfo)] {
        rides.filter { $0.info.allows(heightCm: heightCm) }
    }

    private var ineligibleRides: [(name: String, info: RideInfo)] {
        rides.filter { !$0.info.allows(heightCm: heightCm) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Resort", selection: $resort) {
                    ForEach(Self.choices, id: \.self) { Text(label(for: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Use centimetres", isOn: useCmBinding)
                Stepper(HeightFormat.guest(cm: heightCm, metric: useCm),
                        value: $heightCm, in: 60...205, step: useCm ? 1 : 2.54)
            } header: { Text("Child's height") } footer: {
                if !resort.isOrlando {
                    Text("Japan heights are the parks' published minimums in cm. Some rides also require an adult to ride along below a higher height — check the sign at the entrance.")
                }
            }

            Section {
                Label("\(eligibleRides.count) of \(rides.count) attractions eligible",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Section("Can ride (\(eligibleRides.count))") {
                ForEach(eligibleRides, id: \.name) { (name, info) in
                    HStack {
                        Label(name, systemImage: info.type.systemImage)
                            .font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(HeightFormat.short(info, metric: useCm) ?? "No req")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !ineligibleRides.isEmpty {
                Section("Too short (\(ineligibleRides.count))") {
                    ForEach(ineligibleRides, id: \.name) { (name, info) in
                        HStack {
                            Label(name, systemImage: info.type.systemImage)
                                .font(.subheadline).lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                            Text("Need \(HeightFormat.short(info, metric: useCm) ?? "")")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Height Checker")
        .onAppear {
            let current = appState.selectedResort
            resort = current.isOrlando ? .disney : current
        }
    }
}

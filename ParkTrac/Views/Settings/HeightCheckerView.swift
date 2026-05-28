import SwiftUI

struct HeightCheckerView: View {
    @State private var heightInches: Int = 48
    @State private var useCm = false

    private var displayHeight: String {
        if useCm { return "\(Int(Double(heightInches) * 2.54)) cm" }
        let ft = heightInches / 12; let inches = heightInches % 12
        return "\(ft)' \(inches)\""
    }

    private var eligibleRides: [(name: String, info: RideInfo)] {
        rideMetadata
            .filter { (_, info) in info.heightInches == nil || info.heightInches! <= heightInches }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private var ineligibleRides: [(name: String, info: RideInfo)] {
        rideMetadata
            .filter { (_, info) in (info.heightInches ?? 0) > heightInches }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use centimetres", isOn: $useCm)
                Stepper("\(displayHeight)", value: $heightInches, in: 24...80)
            } header: { Text("Child's height") }

            Section {
                Label("\(eligibleRides.count) of \(rideMetadata.count) attractions eligible",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Section("Can ride (\(eligibleRides.count))") {
                ForEach(eligibleRides, id: \.name) { (name, info) in
                    HStack {
                        Label(name, systemImage: info.type.systemImage)
                            .font(.subheadline).lineLimit(1)
                        Spacer()
                        if let h = info.heightInches {
                            Text("\(h)\"").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("No req").font(.caption).foregroundStyle(.secondary)
                        }
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
                            Text("Need \(info.heightInches ?? 0)\"")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Height Checker")
    }
}

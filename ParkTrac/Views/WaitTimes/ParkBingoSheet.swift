import SwiftUI

/// A checklist challenge — every ride in a park, ridden this trip. Pure progress numbers come
/// from `ParkBingo.progress`; this just lists the two groups.
struct ParkBingoSheet: View {
    let parkName: String
    let ridden: [String]
    let remaining: [String]

    @Environment(\.dismiss) private var dismiss

    private var total: Int { ridden.count + remaining.count }
    private var fraction: Double { total > 0 ? Double(ridden.count) / Double(total) : 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(ridden.count) of \(total) rides this trip")
                            .font(.subheadline.weight(.semibold))
                        ProgressView(value: fraction).tint(.purple)
                    }
                    .padding(.vertical, 4)
                }
                if !remaining.isEmpty {
                    Section("Still to Ride") {
                        ForEach(remaining, id: \.self) { name in
                            Label(name, systemImage: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !ridden.isEmpty {
                    Section("Ridden") {
                        ForEach(ridden, id: \.self) { name in
                            Label(name, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("\(parkName) Bingo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

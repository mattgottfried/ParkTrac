import SwiftUI

/// A checklist challenge — every ride in a park, ridden this trip. Pure progress numbers come
/// from `ParkBingo.progress`; this just lists the two groups.
struct ParkBingoSheet: View {
    let title: String
    let ridden: [String]
    let remaining: [String]
    /// By `RideType` — only rides with known metadata are categorized ("Ride-type challenge").
    var byType: [(type: RideType, ridden: Int, total: Int)] = []

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
                if !byType.isEmpty {
                    Section("By Ride Type") {
                        ForEach(byType, id: \.type) { entry in
                            HStack {
                                Label(entry.type.rawValue, systemImage: entry.type.systemImage)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(entry.ridden) of \(entry.total)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(entry.ridden == entry.total ? .green : .secondary)
                            }
                        }
                    }
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
            .navigationTitle("\(title) Bingo")
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

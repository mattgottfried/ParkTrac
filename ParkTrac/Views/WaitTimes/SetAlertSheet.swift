import SwiftUI
import SwiftData

struct SetAlertSheet: View {
    let ride: DisplayRide
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var threshold = 30

    var body: some View {
        NavigationStack {
            Form {
                Section("Notify me when wait drops to:") {
                    Picker("Threshold", selection: $threshold) {
                        ForEach([10, 15, 20, 30, 45, 60], id: \.self) { m in
                            Text("\(m) minutes").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Section {
                    Text("You'll get a notification the next time \(ride.name)'s wait drops to \(threshold) minutes or less.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Set Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set Alert") { saveAlert() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveAlert() {
        // Remove any existing alert for this ride first
        let existing = (try? context.fetch(FetchDescriptor<RideAlert>())) ?? []
        for old in existing.filter({ $0.rideId == ride.id }) { context.delete(old) }
        let alert = RideAlert(rideId: ride.id, rideName: ride.name, thresholdMinutes: threshold)
        context.insert(alert)
        try? context.save()
        Task { await NotificationService.shared.requestAuthorization() }
        dismiss()
    }
}

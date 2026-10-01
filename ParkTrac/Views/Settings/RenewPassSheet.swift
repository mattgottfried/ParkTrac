import SwiftUI

/// Enter the new pass's price, expiry, and tier when renewing — the old values are snapshotted
/// into a `PassPeriod` by the caller before this ever runs; this sheet just collects the new ones.
struct RenewPassSheet: View {
    let resortLabel: String
    let tierOptions: [String]
    let currentTierRaw: String
    let oldCost: Double
    let oldExpiry: Date?
    let onRenew: (_ newCost: Double, _ newExpiry: Date, _ newTierRaw: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var costText = ""
    @State private var expiry = Date()
    @State private var tierRaw = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Pass Tier", selection: $tierRaw) {
                        ForEach(tierOptions, id: \.self) { Text($0).tag($0) }
                    }
                    HStack {
                        Text("New Cost")
                        Spacer()
                        Text("$")
                        TextField("e.g. 999", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("New Expiry", selection: $expiry, displayedComponents: .date)
                } footer: {
                    Text("Your old \(resortLabel) pass (\(oldCost, format: .currency(code: "USD"))) moves into Lifetime Savings history — it keeps counting toward your all-time total, separate from this pass year.")
                        .font(.caption)
                }
            }
            .navigationTitle("Renew \(resortLabel) Pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onRenew(Double(costText) ?? 0, expiry, tierRaw)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(costText) == nil || tierRaw.isEmpty)
                }
            }
            .onAppear {
                tierRaw = currentTierRaw
                expiry = Calendar.current.date(byAdding: .year, value: 1, to: oldExpiry ?? .now) ?? .now
            }
        }
        .presentationDetents([.medium])
    }
}

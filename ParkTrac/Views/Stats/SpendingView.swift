import SwiftUI
import SwiftData

struct SpendingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \PurchaseLog.date, order: .reverse) private var allPurchases: [PurchaseLog]

    @State private var showAddSheet = false

    private var resort: String { appState.selectedResort.rawValue }
    private var resortPurchases: [PurchaseLog] { allPurchases.filter { $0.resort == resort } }

    private var todayTotal: Double {
        resortPurchases.filter { Calendar.current.isDateInToday($0.date) }.map(\.amount).reduce(0, +)
    }
    private var tripTotal: Double { resortPurchases.map(\.amount).reduce(0, +) }

    private let categories = ["Food", "Merchandise", "Tickets", "Lightning Lane", "Other"]
    private let categoryColors: [String: Color] = [
        "Food": .orange, "Merchandise": .blue, "Tickets": .purple,
        "Lightning Lane": .yellow, "Other": .gray
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        spendStat(label: "Today", value: todayTotal, color: .blue)
                        Divider()
                        spendStat(label: "This Trip", value: tripTotal, color: .green)
                    }
                    .frame(height: 70)
                }

                if !resortPurchases.isEmpty {
                    Section("By Category") {
                        ForEach(categories, id: \.self) { cat in
                            let total = resortPurchases.filter { $0.category == cat }.map(\.amount).reduce(0, +)
                            if total > 0 {
                                HStack {
                                    Circle().fill(categoryColors[cat] ?? .gray).frame(width: 10, height: 10)
                                    Text(cat)
                                    Spacer()
                                    Text(total, format: .currency(code: "USD")).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("All Purchases") {
                    if resortPurchases.isEmpty {
                        Text("No purchases logged yet.").foregroundStyle(.secondary).font(.subheadline)
                    } else {
                        ForEach(resortPurchases) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.note.isEmpty ? p.category : p.note)
                                        .font(.subheadline)
                                    Text("\(p.category) · \(p.date, style: .date)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(p.amount, format: .currency(code: "USD"))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet { context.delete(resortPurchases[i]) }
                        }
                    }
                }
            }
            .navigationTitle("Spending")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: PassSavingsView()) {
                        Label("Pass Savings", systemImage: "dollarsign.arrow.circlepath")
                            .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddSheet) { AddPurchaseView(resort: resort) }
        }
    }

    private func spendStat(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value, format: .currency(code: "USD"))
                .font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AddPurchaseView: View {
    let resort: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amount = ""
    @State private var category = "Food"
    @State private var note = ""
    @State private var isAPEligible = true
    @State private var selectedPark = ""
    @State private var showLocationPicker = false
    private let categories = ["Food", "Merchandise", "Tickets", "Lightning Lane", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        Text("$")
                        TextField("0.00", text: $amount).keyboardType(.decimalPad)
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                }
                if category == "Food" || category == "Merchandise" {
                    Section {
                        Button {
                            showLocationPicker = true
                        } label: {
                            HStack {
                                Text(note.isEmpty ? "Choose location…" : note)
                                    .foregroundStyle(note.isEmpty ? Color.secondary : Color.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Toggle("AP Discount Eligible", isOn: $isAPEligible)
                    } header: {
                        Text("Location")
                    } footer: {
                        Text("AP discount only applies at select locations.")
                            .font(.caption)
                    }
                } else {
                    Section("Note (optional)") {
                        TextField("e.g. Mickey pretzel", text: $note)
                    }
                }
            }
            .navigationTitle("Add Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(amount), value > 0 {
                            context.insert(PurchaseLog(amount: value, category: category, resort: resort, note: note, isAPEligible: isAPEligible))
                            try? context.save()
                            dismiss()
                        }
                    }
                    .disabled(Double(amount) == nil || (Double(amount) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(
                resort: resort,
                category: category,
                selectedPark: $selectedPark,
                selectedLocation: $note,
                isAPEligible: $isAPEligible
            )
            .presentationDetents([.large])
        }
    }
}

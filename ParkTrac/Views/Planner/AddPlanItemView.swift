import SwiftUI
import SwiftData

struct AddPlanItemView: View {
    let resort: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(WaitTimesViewModel.self) private var waitTimesVM

    @State private var title = ""
    @State private var kind = "ride"
    @State private var scheduledTime: Date = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var hasTime = false
    @State private var parkName = ""
    @State private var notes = ""
    @State private var llStart: Date = .now
    @State private var llEnd: Date = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @State private var rideId = ""
    @State private var showAutoComplete = false

    init(resort: String, prefillRide: DisplayRide? = nil, prefillPark: String = "") {
        self.resort = resort
        _title    = State(initialValue: prefillRide?.name ?? "")
        _parkName = State(initialValue: prefillPark)
        _rideId   = State(initialValue: prefillRide?.id ?? "")
        _kind     = State(initialValue: "ride")
    }

    private let kinds = [("ride", "figure.jumprope", "Ride"),
                         ("show", "theatermasks.fill", "Show"),
                         ("dining", "fork.knife", "Dining"),
                         ("ll", "bolt.fill", "LL"),
                         ("note", "note.text", "Note")]

    private var rideSuggestions: [DisplayRide] {
        guard kind == "ride", !title.isEmpty else { return [] }
        return Array(waitTimesVM.allRides
            .filter { $0.name.localizedCaseInsensitiveContains(title) && $0.isOperating }
            .prefix(5))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Kind", selection: $kind) {
                        ForEach(kinds, id: \.0) { k in
                            Label(k.2, systemImage: k.1).tag(k.0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    TextField(kind == "ll" ? "Ride name" : "Name", text: $title)
                        .onChange(of: title) { _, _ in
                            rideId = ""  // clear prefill if user edits
                        }

                    // Ride autocomplete suggestions
                    if kind == "ride" && !rideSuggestions.isEmpty && rideId.isEmpty {
                        ForEach(rideSuggestions) { ride in
                            Button {
                                title = ride.name
                                rideId = ride.id
                                parkName = waitTimesVM.currentParks
                                    .first(where: { $0.id == ride.parkId })?.name ?? parkName
                            } label: {
                                HStack {
                                    Text(ride.name)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    if let wait = ride.waitMinutes {
                                        Text("\(wait)m")
                                            .font(.caption)
                                            .foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        }
                    }

                    TextField("Park (optional)", text: $parkName)
                }

                if kind == "ll" {
                    Section("Return Window") {
                        DatePicker("Start", selection: $llStart, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $llEnd, displayedComponents: .hourAndMinute)
                    }
                } else {
                    Section("Time (optional)") {
                        Toggle("Set a time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Time", selection: $scheduledTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes…", text: $notes, axis: .vertical).lineLimit(3)
                }
            }
            .navigationTitle("Add to My Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let maxOrder = (try? context.fetch(FetchDescriptor<PlanItem>()))?.map(\.sortOrder).max() ?? 0
        let item = PlanItem(
            title: title.trimmingCharacters(in: .whitespaces),
            kind: kind,
            parkName: parkName,
            resort: resort,
            notes: notes,
            sortOrder: maxOrder + 1
        )
        item.rideId = rideId.isEmpty ? nil : rideId
        if kind == "ll" {
            item.llReturnStart = llStart
            item.llReturnEnd = llEnd
            Task {
                await NotificationService.shared.requestAuthorization()
                NotificationService.shared.scheduleLLReminder(
                    passId: item.persistentModelID.hashValue.description,
                    rideName: item.title,
                    returnEnd: llEnd
                )
            }
        } else if hasTime {
            item.scheduledTime = scheduledTime
        }
        context.insert(item)
        try? context.save()
        dismiss()
    }
}

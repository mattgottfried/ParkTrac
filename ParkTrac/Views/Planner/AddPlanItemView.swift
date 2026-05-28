import SwiftUI
import SwiftData

struct AddPlanItemView: View {
    let resort: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title = ""
    @State private var kind = "ride"
    @State private var scheduledTime: Date = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var hasTime = false
    @State private var parkName = ""
    @State private var notes = ""
    @State private var llStart: Date = .now
    @State private var llEnd: Date = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now

    private let kinds = [("ride", "figure.jumprope", "Ride"),
                         ("show", "theatermasks.fill", "Show"),
                         ("dining", "fork.knife", "Dining"),
                         ("ll", "bolt.fill", "LL"),
                         ("note", "note.text", "Note")]

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

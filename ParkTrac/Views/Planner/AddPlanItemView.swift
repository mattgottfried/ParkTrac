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
    @State private var showLocationPicker = false
    @State private var showActivityPicker = false

    init(resort: String, prefillRide: DisplayRide? = nil, prefillPark: String = "") {
        self.resort = resort
        _title    = State(initialValue: prefillRide?.name ?? "")
        _parkName = State(initialValue: prefillPark)
        _rideId   = State(initialValue: prefillRide?.id ?? "")
        _kind     = State(initialValue: "ride")
    }

    // MARK: - Type config

    private struct KindConfig {
        let id: String
        let icon: String
        let label: String
        let color: Color
    }

    private let kinds: [KindConfig] = [
        .init(id: "ride",   icon: "figure.jumprope",  label: "Ride",   color: .blue),
        .init(id: "show",   icon: "theatermasks.fill", label: "Show",   color: .purple),
        .init(id: "dining", icon: "fork.knife",        label: "Dining", color: .orange),
        .init(id: "ll",     icon: "bolt.fill",         label: "LL",     color: .yellow),
        .init(id: "note",   icon: "note.text",         label: "Note",   color: .gray),
    ]

    private var currentKind: KindConfig { kinds.first(where: { $0.id == kind }) ?? kinds[0] }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // MARK: Type picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Type").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        HStack(spacing: 10) {
                            ForEach(kinds, id: \.id) { k in
                                KindButton(config: k, isSelected: kind == k.id) {
                                    withAnimation(.spring(response: 0.25)) {
                                        kind = k.id
                                        if k.id != "ride" { rideId = "" }
                                        if k.id == "note" { title = ""; parkName = "" }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // MARK: Details card
                    VStack(spacing: 0) {
                        if kind == "dining" {
                            // Location picker for dining
                            Button {
                                showLocationPicker = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Restaurant")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text(title.isEmpty ? "Choose restaurant…" : title)
                                            .font(.subheadline)
                                            .foregroundStyle(title.isEmpty ? Color.secondary : Color.primary)
                                        if !parkName.isEmpty {
                                            Text(parkName).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)

                        } else if kind == "ride" || kind == "show" || kind == "ll" {
                            // Activity picker — park → ride/show drill-down
                            Button {
                                showActivityPicker = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(kind == "show" ? "Show" : "Ride")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text(title.isEmpty ? "Choose \(kind == "show" ? "show" : "ride")…" : title)
                                            .font(.subheadline)
                                            .foregroundStyle(title.isEmpty ? Color.secondary : Color.primary)
                                        if !parkName.isEmpty {
                                            Text(parkName).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)

                        } else if kind == "note" {
                            // Note — just a text area
                            TextField("Write a note…", text: $title, axis: .vertical)
                                .lineLimit(3...6)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal)

                        } else {
                            TextField("Name", text: $title)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal)
                        }
                    }

                    // MARK: Return window (LL only)
                    if kind == "ll" {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Return Window").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                HStack {
                                    Text("From").font(.subheadline).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                                    DatePicker("", selection: $llStart, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                }
                                .padding(.horizontal).padding(.vertical, 10)
                                Divider().padding(.leading, 64)
                                HStack {
                                    Text("To").font(.subheadline).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                                    DatePicker("", selection: $llEnd, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                }
                                .padding(.horizontal).padding(.vertical, 10)
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                            // Preview pill
                            HStack {
                                Image(systemName: "clock.fill").foregroundStyle(.yellow)
                                Text("Return \(llWindowText)")
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal)

                    } else if kind != "note" {
                        // MARK: Schedule time
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Time").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                Toggle("Set a time", isOn: $hasTime)
                                    .padding(.horizontal).padding(.vertical, 10)
                                if hasTime {
                                    Divider().padding(.leading)
                                    DatePicker("", selection: $scheduledTime, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .padding(.horizontal).padding(.vertical, 10)
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal)
                    }

                    // MARK: Notes (not for LL or note type)
                    if kind != "note" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            TextField("Optional…", text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal)
                    }

                    // MARK: Add button
                    Button(action: save) {
                        Label("Add to My Day", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(currentKind.color, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .padding(.top, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add to My Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showActivityPicker) {
                ActivityPickerSheet(
                    kind: kind,
                    selectedTitle: $title,
                    selectedPark: $parkName,
                    selectedRideId: $rideId
                )
                .environment(waitTimesVM)
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showLocationPicker) {
                let dummy = Binding<Bool>(get: { true }, set: { _ in })
                LocationPickerView(
                    resort: resort,
                    category: "Food",
                    selectedPark: $parkName,
                    selectedLocation: $title,
                    isAPEligible: dummy
                )
                .presentationDetents([.large])
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Helpers

    // MARK: - Ride Suggestion Row (extracted for type-check budget)

    // MARK: - Kind Button (extracted for type-check budget)

    private struct KindButton: View {
        let config: KindConfig
        let isSelected: Bool
        let onTap: () -> Void
        var body: some View {
            Button(action: onTap) {
                VStack(spacing: 6) {
                    Image(systemName: config.icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(config.label).font(.caption2.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? config.color : config.color.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(isSelected ? Color.white : config.color)
            }
            .buttonStyle(.plain)
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    private var llWindowText: String {
        "\(Self.timeFmt.string(from: llStart)) – \(Self.timeFmt.string(from: llEnd))"
    }

    private func waitColor(_ minutes: Int) -> Color {
        if minutes < 30 { return .green }
        if minutes < 60 { return Color(red: 1, green: 0.75, blue: 0) }
        return .red
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
                    passId: item.id.uuidString,
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

// MARK: - Activity Picker Sheet (Ride / Show / LL drill-down)

private struct ActivityPickerSheet: View {
    let kind: String                    // "ride", "show", or "ll"
    @Binding var selectedTitle: String
    @Binding var selectedPark: String
    @Binding var selectedRideId: String

    @Environment(WaitTimesViewModel.self) private var waitTimesVM
    @Environment(\.dismiss) private var dismiss
    @State private var drillPark: ParkEntity? = nil
    @State private var searchText = ""

    private var isShowPicker: Bool { kind == "show" }

    private var filteredRides: [DisplayRide] {
        guard let park = drillPark else { return [] }
        return waitTimesVM.allRides
            .filter { $0.parkId == park.id && $0.isOperating }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    private var filteredShows: [DisplayShow] {
        guard let park = drillPark else { return [] }
        return waitTimesVM.currentShows
            .filter { $0.parkId == park.id }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if let park = drillPark {
                    activityList(for: park)
                } else {
                    parkList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if drillPark != nil {
                        Button("Back") { drillPark = nil; searchText = "" }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var parkList: some View {
        List(waitTimesVM.currentParks, id: \.id) { park in
            Button {
                drillPark = park
                searchText = ""
            } label: {
                HStack {
                    Text(park.name).foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(isShowPicker ? "Select Show" : "Select Ride")
    }

    private func activityList(for park: ParkEntity) -> some View {
        Group {
            if isShowPicker {
                List(filteredShows) { show in
                    Button {
                        selectedTitle = show.name
                        selectedPark = park.name
                        selectedRideId = ""
                        dismiss()
                    } label: {
                        ShowPickerRow(show: show)
                    }
                }
            } else {
                List(filteredRides) { ride in
                    Button {
                        selectedTitle = ride.name
                        selectedPark = park.name
                        selectedRideId = ride.id
                        dismiss()
                    } label: {
                        RidePickerRow(ride: ride)
                    }
                }
            }
        }
        .navigationTitle(park.name)
        .searchable(text: $searchText, prompt: "Search")
    }
}

// MARK: - Row cells (extracted for type-check budget)

private struct RidePickerRow: View {
    let ride: DisplayRide
    var body: some View {
        HStack {
            Text(ride.name).foregroundStyle(Color.primary)
            Spacer()
            if let wait = ride.waitMinutes {
                let color: Color = wait < 30 ? .green : (wait < 60 ? Color(red:1,green:0.75,blue:0) : .red)
                Text("\(wait)m")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color, in: Capsule())
            } else {
                Text("Open").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ShowPickerRow: View {
    let show: DisplayShow
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
    var body: some View {
        HStack {
            Text(show.name).foregroundStyle(Color.primary)
            Spacer()
            if let next = show.nextShowtime {
                Text(Self.fmt.string(from: next))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

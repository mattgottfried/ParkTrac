import SwiftUI

/// Trip countdown, pre-trip checklist and the yen ↔ dollar rate. Reached from Stats and
/// from the countdown card in My Day. Syncs to both phones through iCloud.
struct TripPlannerView: View {
    @State private var trips = TripService.shared
    @State private var currency = CurrencyConverter.shared

    @State private var newItem = ""
    @State private var manualRate = ""
    @State private var showDeleteConfirm = false
    @FocusState private var addFocused: Bool

    var body: some View {
        List {
            if let trip = trips.trip {
                tripSections(trip)
            } else {
                ContentUnavailableView {
                    Label("No Trip Planned", systemImage: "airplane")
                } description: {
                    Text("Add your trip for a countdown, a pre-trip checklist you both can tick off, and yen ↔ dollar prices.")
                } actions: {
                    Button("Plan Japan Trip") { startJapanTrip() }
                        .buttonStyle(.borderedProminent)
                }
            }

            currencySection
        }
        .navigationTitle("Trip Planner")
        .task { await currency.refresh() }
        .confirmationDialog("Delete this trip?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) { trips.save(nil) }
        } message: {
            Text("Removes the dates and checklist from both phones.")
        }
    }

    // MARK: Trip

    @ViewBuilder
    private func tripSections(_ trip: Trip) -> some View {
        Section {
            if let text = trips.countdownText {
                Label(text, systemImage: "calendar.badge.clock")
                    .font(.headline)
            } else {
                Label("Trip complete", systemImage: "checkmark.seal")
            }
            TextField("Trip name", text: binding(\.name, trip))
            DatePicker("Starts", selection: binding(\.startDate, trip), displayedComponents: .date)
            DatePicker("Ends", selection: binding(\.endDate, trip), in: trip.startDate..., displayedComponents: .date)
        } header: {
            Text("Trip")
        }

        Section {
            let done = trip.checklist.filter(\.isDone).count
            if !trip.checklist.isEmpty {
                ProgressView(value: Double(done), total: Double(trip.checklist.count)) {
                    Text("\(done) of \(trip.checklist.count) done").font(.caption)
                }
            }
            ForEach(trip.checklist) { item in
                Button {
                    trips.update { t in
                        if let i = t.checklist.firstIndex(where: { $0.id == item.id }) { t.checklist[i].isDone.toggle() }
                    }
                } label: {
                    HStack {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                        Text(item.title)
                            .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                            .strikethrough(item.isDone)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item.isDone ? .isSelected : [])
            }
            .onDelete { offsets in trips.update { $0.checklist.remove(atOffsets: offsets) } }
            .onMove { from, to in trips.update { $0.checklist.move(fromOffsets: from, toOffset: to) } }

            HStack {
                TextField("Add item", text: $newItem)
                    .focused($addFocused)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                Button("Add", action: addItem)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Before We Go")
        } footer: {
            Text("Shared with your other devices on the same iCloud account. Swipe to delete.")
        }

        Section {
            Button("Delete Trip", role: .destructive) { showDeleteConfirm = true }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Trip, T>, _ fallback: Trip) -> Binding<T> {
        Binding(
            get: { (trips.trip ?? fallback)[keyPath: keyPath] },
            set: { value in trips.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func addItem() {
        let title = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        trips.update { $0.checklist.append(.init(title: title)) }
        newItem = ""
        addFocused = true
    }

    private func startJapanTrip() {
        // Placeholder dates in November — adjust them above
        let cal = Calendar.current
        let year = cal.component(.year, from: .now) + (cal.component(.month, from: .now) > 11 ? 1 : 0)
        let start = cal.date(from: DateComponents(year: year, month: 11, day: 1)) ?? .now
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        trips.save(.japan(start: start, end: end))
    }

    // MARK: Currency

    private var currencySection: some View {
        Section {
            LabeledContent("$1 =", value: "¥\(Int(currency.yenPerDollar.rounded()))")
            LabeledContent("¥1,000 ≈", value: currency.dollarsText(yen: 1000).replacingOccurrences(of: "≈ ", with: ""))
            HStack {
                TextField("Set rate (¥ per $1)", text: $manualRate)
                    .keyboardType(.decimalPad)
                Button("Set") {
                    if let rate = Double(manualRate.replacingOccurrences(of: ",", with: ".")) {
                        currency.setManual(rate)
                        manualRate = ""
                    }
                }
                .disabled(Double(manualRate.replacingOccurrences(of: ",", with: ".")) == nil)
            }
            if currency.isManual {
                Button("Use Live Rate") { Task { await currency.useLiveRate() } }
            }
        } header: {
            Text("Yen ↔ Dollar")
        } footer: {
            if currency.isManual {
                Text("Using your rate. Spending at the Japan resorts shows ≈ dollars with it.")
            } else if let updated = currency.updatedAt {
                Text("Live rate, updated \(updated.formatted(.relative(presentation: .named))). Spending at the Japan resorts shows ≈ dollars beside yen.")
            } else {
                Text("Using ¥\(Int(CurrencyConverter.defaultYenPerDollar)) per $1 until a live rate loads.")
            }
        }
    }
}

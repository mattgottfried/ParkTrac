import SwiftUI
import SwiftData

struct BookReturnTimeSheet: View {
    let ride: DisplayRide
    let parkGroup: ParkGroup
    let parkName: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var passKind: PassKind = .ll
    @State private var returnStart = Date()
    @State private var trackNextBooking = false
    @State private var nextBookingAt = Date().addingTimeInterval(5400)

    /// Commonly-cited modern Lightning Lane re-booking interval (90 min),
    /// presented as an editable estimate — not asserted as authoritative.
    private static let nextBookingInterval: TimeInterval = 90 * 60

    private var isOpenEnded: Bool { passKind == .das || passKind == .aap }

    private var returnEnd: Date {
        isOpenEnded
            ? .distantFuture
            : returnStart.addingTimeInterval(3600)
    }

    enum PassKind: String, Identifiable {
        case ll          = "Lightning Lane"
        case das         = "DAS"
        case expressNow  = "Express Now"
        case aap         = "AAP"
        // Tokyo Disney Resort
        case priorityPass  = "Priority Pass"
        case premierAccess = "Premier Access"
        // Universal Studios Japan
        case expressPass   = "Express Pass"
        var id: Self { self }
        var icon: String {
            switch self {
            case .ll, .expressNow, .priorityPass, .premierAccess: return "bolt.fill"
            case .expressPass:     return "ticket.fill"
            case .das, .aap:       return "figure.roll"
            }
        }
    }

    private var availableKinds: [PassKind] {
        switch parkGroup {
        case .disney:
            var kinds: [PassKind] = []
            if appState.hasLightningLane { kinds.append(.ll) }
            if appState.hasDAS { kinds.append(.das) }
            return kinds
        case .universal:
            var kinds: [PassKind] = []
            if appState.universalExpressType == .expressNow { kinds.append(.expressNow) }
            if appState.hasAAP { kinds.append(.aap) }
            return kinds
        case .tokyoDisney:
            return [.priorityPass, .premierAccess]
        case .universalJapan:
            return [.expressPass]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if availableKinds.count > 1 {
                    Section {
                        Picker("Pass type", selection: $passKind) {
                            ForEach(availableKinds) { kind in
                                Label(kind.rawValue, systemImage: kind.icon).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                Section {
                    DatePicker("Return time", selection: $returnStart, displayedComponents: .hourAndMinute)
                    if !isOpenEnded {
                        HStack {
                            Text("Closes")
                            Spacer()
                            Text(returnStart.addingTimeInterval(3600), style: .time)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(ride.name)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if isOpenEnded {
                            Text("DAS/AAP return times are valid until park close — no expiry window.")
                        } else {
                            Text("Your window closes 1 hour after the return time. You'll get a notification 10 minutes before it closes.")
                        }
                        if passKind == .expressNow {
                            Text("Express Now allows one use per ride.")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }

                if !isOpenEnded {
                    Section {
                        Toggle("Track next booking eligibility", isOn: $trackNextBooking)
                        if trackNextBooking {
                            DatePicker("Eligible at", selection: $nextBookingAt, displayedComponents: .hourAndMinute)
                        }
                    } footer: {
                        if trackNextBooking {
                            Text("Estimated next Lightning Lane booking time (default: 90 min after your return time). This is an estimate — always verify eligibility in the official app.")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Log Return Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                }
            }
            .onAppear {
                passKind = availableKinds.first ?? .ll
                applyDefaultReturn()
                nextBookingAt = returnStart.addingTimeInterval(Self.nextBookingInterval)
            }
            .onChange(of: passKind) { _, _ in applyDefaultReturn() }
            .onChange(of: returnStart) { _, newValue in
                // Keep the estimate in step with the return time until the
                // user opts in — once enabled, their edits are preserved.
                if !trackNextBooking {
                    nextBookingAt = newValue.addingTimeInterval(Self.nextBookingInterval)
                }
            }
        }
    }

    /// DAS/AAP return times come from the current standby wait (per-pass rule in
    /// `AccessPass.returnDelayMinutes`); timed passes default to now. Either is editable.
    private func applyDefaultReturn() {
        switch passKind {
        case .aap: returnStart = AccessPass.aap.estimatedReturn(postedWait: ride.waitMinutes)
        case .das: returnStart = AccessPass.das.estimatedReturn(postedWait: ride.waitMinutes)
        case .ll, .expressNow, .priorityPass, .premierAccess, .expressPass: returnStart = Date()
        }
    }

    private func save() {
        // PlanItem + Live Activity + reminder (return-open for DAS/AAP, closing-soon for timed)
        ReturnTimeLogger.log(
            passLabel: passKind.rawValue,
            isOpenEnded: isOpenEnded,
            rideId: ride.id,
            rideName: ride.name,
            parkName: parkName,
            resort: parkGroup.rawValue,
            returnStart: returnStart,
            returnEnd: returnEnd,
            context: context
        )
        // Optional concurrent "next booking eligibility" countdown (LL / Express
        // Now only). Runs alongside the return-time activity — ActivityKit
        // supports multiple concurrent activities from one app.
        if trackNextBooking && !isOpenEnded && nextBookingAt > .now {
            LiveActivityManager.startNextBooking(rideName: ride.name, eligibleAt: nextBookingAt,
                                                 resortRaw: parkGroup.rawValue)
        }
    }
}

// MARK: - Area Timed Entry (USJ)

/// Logs a Super Nintendo World (or other area) timed entry window booked in the USJ app.
struct AreaEntrySheet: View {
    let resort: ParkGroup

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var area = AreaEntry.presets[0]
    @State private var start = Date()
    @State private var windowMinutes = AreaEntry.defaultWindowMinutes

    private var end: Date { AreaEntry.window(start: start, minutes: windowMinutes).end }
    private var canSave: Bool { !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Area") {
                    Picker("Area", selection: $area) {
                        ForEach(AreaEntry.presets, id: \.self) { Text($0).tag($0) }
                        if !AreaEntry.presets.contains(area) { Text(area).tag(area) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    TextField("Other area", text: $area)
                }

                Section {
                    DatePicker("Entry from", selection: $start, displayedComponents: .hourAndMinute)
                    Stepper("Window: \(windowMinutes) min", value: $windowMinutes, in: 15...240, step: 15)
                    HStack {
                        Text("Enter by")
                        Spacer()
                        Text(end, style: .time).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Use the times on your Area Timed Entry ticket in the USJ app. You'll get a notification when the window opens and 10 minutes before it closes.")
                }
            }
            .navigationTitle("Log Timed Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ReturnTimeLogger.logAreaEntry(area: area, start: start, windowMinutes: windowMinutes,
                                                      resort: resort, context: context)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

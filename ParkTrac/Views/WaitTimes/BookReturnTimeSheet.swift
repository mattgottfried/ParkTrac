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
        var id: Self { self }
        var planKind: String {
            switch self {
            case .ll, .expressNow: return "ll"
            case .das, .aap:       return "aap"
            }
        }
        var icon: String {
            switch self {
            case .ll, .expressNow: return "bolt.fill"
            case .das, .aap:       return "figure.roll"
            }
        }
    }

    private var availableKinds: [PassKind] {
        if parkGroup == .disney {
            var kinds: [PassKind] = []
            if appState.hasLightningLane { kinds.append(.ll) }
            if appState.hasDAS { kinds.append(.das) }
            return kinds
        } else {
            var kinds: [PassKind] = []
            if appState.universalExpressType == .expressNow { kinds.append(.expressNow) }
            if appState.hasAAP { kinds.append(.aap) }
            return kinds
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
            }
        }
    }

    private func save() {
        let item = PlanItem(
            title: ride.name,
            kind: passKind.planKind,
            rideId: ride.id,
            parkName: parkName,
            resort: parkGroup.rawValue
        )
        item.llReturnStart = returnStart
        item.llReturnEnd = returnEnd
        context.insert(item)
        try? context.save()
        let passId = "\(ride.id)-\(Int(returnStart.timeIntervalSince1970))"
        NotificationService.shared.scheduleLLReminder(
            passId: passId,
            rideName: ride.name,
            returnEnd: returnEnd
        )
    }
}

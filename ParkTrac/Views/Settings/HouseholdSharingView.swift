import SwiftUI

struct HouseholdSharingView: View {
    @State private var service = HouseholdSyncService.shared
    @State private var showJoinSheet = false
    @State private var showLeaveConfirm = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        Form {
            if let code = service.currentCode {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Household Code")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .tracking(2)
                    }
                    .padding(.vertical, 4)

                    if let joinedAt = service.joinedAt {
                        HStack {
                            Text("Joined")
                            Spacer()
                            Text(Self.dateFmt.string(from: joinedAt)).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Label("Sync Status", systemImage: service.isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                        Spacer()
                        if service.isSyncing {
                            Text("Syncing…").foregroundStyle(.secondary)
                        } else if let lastSyncedAt = service.lastSyncedAt {
                            Text("Synced \(Self.dateFmt.string(from: lastSyncedAt))").foregroundStyle(.secondary)
                        } else {
                            Text("Not synced yet").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("This Household")
                } footer: {
                    Text("Share this code with your partner — anyone who enters it gets full read/write access to your trip data, so treat it like a shared PIN.")
                }

                Section {
                    Button(role: .destructive) {
                        showLeaveConfirm = true
                    } label: {
                        Label("Leave Household", systemImage: "person.badge.minus")
                    }
                } footer: {
                    Text("Your data stays on this device — leaving just stops it from syncing to the household.")
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Share your whole trip plan", systemImage: "person.2.fill")
                            .font(.headline)
                        Text("Create a household code, or join one someone shared with you, and your bucket list, day plan, dining, ride log, guests, and more stay in sync across both accounts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)

                    Button {
                        showJoinSheet = true
                    } label: {
                        Label("Create or Join a Household", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .navigationTitle("Household Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showJoinSheet) {
            JoinHouseholdSheet()
        }
        .alert("Leave Household?", isPresented: $showLeaveConfirm) {
            Button("Leave", role: .destructive) { service.leave() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This device will stop syncing with the household. Your existing data stays put.")
        }
    }
}

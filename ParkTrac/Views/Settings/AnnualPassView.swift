import SwiftUI

struct AnnualPassView: View {
    @Environment(AppState.self) private var appState
    @State private var showDisneyExpiry = false
    @State private var showUniversalExpiry = false
    @State private var notificationScheduled = false

    var body: some View {
        Form {
            Section("Disney Annual Pass") {
                Picker("Pass Tier", selection: Bindable(appState).disneyPassTier) {
                    ForEach(DisneyPassTier.allCases, id: \.self) { tier in
                        Text(tier.rawValue).tag(tier)
                    }
                }
                if appState.disneyPassTier != .none {
                    Toggle("Set Expiry Date", isOn: $showDisneyExpiry.animation())
                        .onAppear { showDisneyExpiry = appState.disneyPassExpiry != nil }
                    if showDisneyExpiry {
                        DatePicker("Expiry", selection: Binding(
                            get: { appState.disneyPassExpiry ?? Date() },
                            set: { appState.disneyPassExpiry = $0 }
                        ), displayedComponents: .date)
                        if let expiry = appState.disneyPassExpiry {
                            let days = Calendar.current.dateComponents([.day], from: .now, to: expiry).day ?? 0
                            Text(days > 0 ? "Expires in \(days) days" : "Expired")
                                .font(.caption).foregroundStyle(days <= 30 ? .red : .secondary)
                        }
                        Button("Remind Me 30 Days Before Renewal") {
                            if let expiry = appState.disneyPassExpiry {
                                let reminderDate = Calendar.current.date(byAdding: .day, value: -30, to: expiry)!
                                NotificationService.shared.schedulePassRenewalReminder(resort: "Disney", passName: appState.disneyPassTier.rawValue, date: reminderDate)
                                notificationScheduled = true
                            }
                        }
                        .font(.caption)
                        .disabled(appState.disneyPassExpiry == nil)
                    }
                }
            }

            Section("Universal Annual Pass") {
                Picker("Pass Tier", selection: Bindable(appState).universalPassTier) {
                    ForEach(UniversalPassTier.allCases, id: \.self) { tier in
                        Text(tier.rawValue).tag(tier)
                    }
                }
                if appState.universalPassTier != .none {
                    Toggle("Set Expiry Date", isOn: $showUniversalExpiry.animation())
                        .onAppear { showUniversalExpiry = appState.universalPassExpiry != nil }
                    if showUniversalExpiry {
                        DatePicker("Expiry", selection: Binding(
                            get: { appState.universalPassExpiry ?? Date() },
                            set: { appState.universalPassExpiry = $0 }
                        ), displayedComponents: .date)
                        if let expiry = appState.universalPassExpiry {
                            let days = Calendar.current.dateComponents([.day], from: .now, to: expiry).day ?? 0
                            Text(days > 0 ? "Expires in \(days) days" : "Expired")
                                .font(.caption).foregroundStyle(days <= 30 ? .red : .secondary)
                        }
                        Button("Remind Me 30 Days Before Renewal") {
                            if let expiry = appState.universalPassExpiry {
                                let reminderDate = Calendar.current.date(byAdding: .day, value: -30, to: expiry)!
                                NotificationService.shared.schedulePassRenewalReminder(resort: "Universal", passName: appState.universalPassTier.rawValue, date: reminderDate)
                                notificationScheduled = true
                            }
                        }
                        .font(.caption)
                        .disabled(appState.universalPassExpiry == nil)
                    }
                }
            }

            Section {
                NavigationLink {
                    PassSavingsView()
                } label: {
                    Label("Pass Savings", systemImage: "dollarsign.arrow.circlepath")
                }
            } footer: {
                Text("Track tickets, parking, and discounts to see if your pass has paid for itself.")
                    .font(.caption)
            }
        }
        .navigationTitle("Annual Passes")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reminder Set", isPresented: $notificationScheduled) {
            Button("OK") {}
        } message: {
            Text("You'll be notified 30 days before your pass expires.")
        }
    }
}

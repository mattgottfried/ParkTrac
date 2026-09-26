import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @State private var showResetDiningConfirm = false
    @State private var showClearHistoryConfirm = false
    @Query private var allRideLogs: [RideLog]
    @Query private var allPurchases: [PurchaseLog]
    @AppStorage(BookingApp.disney.useShortcutKey) private var disneyViaShortcut = false
    @AppStorage(BookingApp.universal.useShortcutKey) private var universalViaShortcut = false
    @AppStorage(BookingApp.tokyoDisney.useShortcutKey) private var tokyoDisneyViaShortcut = false
    @AppStorage(BookingApp.universalJapan.useShortcutKey) private var universalJapanViaShortcut = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var storageDescription: String {
        switch PersistenceController.storageMode {
        case .cloud: return "On"
        case .localOnly: return "Off — on-device only"
        case .inMemory: return "Temporary — data won't be saved"
        }
    }

    private var storageIcon: String {
        switch PersistenceController.storageMode {
        case .cloud: return "icloud.fill"
        case .localOnly: return "icloud.slash"
        case .inMemory: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        @Bindable var state = appState
        NavigationStack {
            Form {
                // MARK: Resort
                Section {
                    HStack {
                        Label("Current Resort", systemImage: appState.selectedResort.systemImage)
                        Spacer()
                        Text(appState.selectedResort.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        appState.showResortPicker = true
                    } label: {
                        Label("Switch Resort", systemImage: "arrow.left.arrow.right")
                    }
                } header: {
                    Text("Resort")
                }

                // MARK: Annual Passes
                Section {
                    NavigationLink {
                        AnnualPassView()
                    } label: {
                        Label("Annual Passes", systemImage: "creditcard.fill")
                    }
                } header: {
                    Text("Passes")
                }

                // MARK: Map
                Section {
                    Toggle(isOn: $state.defaultMapIsSatellite) {
                        Label("Default to Satellite View", systemImage: "globe.americas.fill")
                    }
                } header: {
                    Text("Map")
                } footer: {
                    Text("When enabled, the map opens in hybrid satellite view instead of standard.")
                }

                // MARK: Rides
                Section {
                    Toggle(isOn: $state.sortRidesAlphabetically) {
                        Label("Sort Rides A–Z", systemImage: "textformat.abc")
                    }
                } header: {
                    Text("Rides")
                } footer: {
                    Text("When off, rides are sorted by wait time with operating attractions first.")
                }

                // MARK: Ratings
                Section {
                    LabeledContent("First Reviewer") {
                        TextField(AppState.defaultRaterOneName, text: $state.raterOneName)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Second Reviewer") {
                        TextField(AppState.defaultRaterTwoName, text: $state.raterTwoName)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(role: .destructive) {
                        showResetDiningConfirm = true
                    } label: {
                        Label("Reset Dining History…", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Dining & Hotel Ratings")
                } footer: {
                    Text("Names shown on the two rating columns. Reset clears every restaurant's visited status and ratings; notes, photos and reservations are kept.")
                }
                .confirmationDialog("Reset Dining History?", isPresented: $showResetDiningConfirm, titleVisibility: .visible) {
                    Button("Reset All Restaurants", role: .destructive) { resetDiningHistory() }
                } message: {
                    Text(PersistenceController.storageMode == .cloud
                         ? "Marks every restaurant as not visited and clears both ratings on all devices signed in to this Apple ID. This can't be undone."
                         : "Marks every restaurant as not visited and clears both ratings. This can't be undone.")
                }

                // MARK: Booking Apps
                Section {
                    Toggle(isOn: $disneyViaShortcut) {
                        Label("Use \"\(BookingApp.disney.shortcutName)\" Shortcut", systemImage: "wand.and.stars")
                    }
                    Toggle(isOn: $universalViaShortcut) {
                        Label("Use \"\(BookingApp.universal.shortcutName)\" Shortcut", systemImage: "wand.and.stars")
                    }
                    Toggle(isOn: $tokyoDisneyViaShortcut) {
                        Label("Use \"\(BookingApp.tokyoDisney.shortcutName)\" Shortcut", systemImage: "wand.and.stars")
                    }
                    Toggle(isOn: $universalJapanViaShortcut) {
                        Label("Use \"\(BookingApp.universalJapan.shortcutName)\" Shortcut", systemImage: "wand.and.stars")
                    }
                    Button {
                        if let url = URL(string: "shortcuts://create-shortcut") { UIApplication.shared.open(url) }
                    } label: {
                        Label("Create Shortcut in the Shortcuts App", systemImage: "plus.app")
                    }
                } header: {
                    Text("Booking Apps")
                } footer: {
                    Text("\"Book in … App\" buttons open the park's website unless you turn on a Shortcut here. To jump straight into the app, create a shortcut named exactly as shown (e.g. \"\(BookingApp.disney.shortcutName)\") with one Open App action for that park's app, then turn it on here.")
                }

                // MARK: Tools
                Section {
                    NavigationLink {
                        HeightCheckerView()
                    } label: {
                        Label("Height Checker", systemImage: "ruler")
                    }
                    NavigationLink {
                        CharacterFinderView()
                    } label: {
                        Label("Character Finder", systemImage: "figure.wave")
                    }
                } header: {
                    Text("Tools")
                }

                // MARK: Data & Sync
                Section {
                    ShareLink(item: DataExport.rideLog(allRideLogs),
                              preview: SharePreview("ThrillTrack Rides.csv")) {
                        Label("Export Ride Log (CSV)", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: DataExport.purchases(allPurchases),
                              preview: SharePreview("ThrillTrack Spending.csv")) {
                        Label("Export Spending (CSV)", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showClearHistoryConfirm = true
                    } label: {
                        Label("Clear Wait-Time History…", systemImage: "chart.line.downtrend.xyaxis")
                    }
                    Button {
                        appState.hasCompletedOnboarding = false
                    } label: {
                        Label("Show Welcome Screen Again", systemImage: "hand.wave")
                    }
                } header: {
                    Text("Data & Sync")
                } footer: {
                    Text("Exports open the share sheet — save to Files or open in Numbers. Wait-time history powers your personal predictions; it's stored only on this device and rebuilds as you use the app.")
                }
                .confirmationDialog("Clear Wait-Time History?", isPresented: $showClearHistoryConfirm, titleVisibility: .visible) {
                    Button("Clear History", role: .destructive) { clearWaitHistory() }
                } message: {
                    Text("Deletes recorded wait-time snapshots and downtime on this device. Community baselines are unaffected, and your rides, plans and ratings are kept.")
                }

                // MARK: About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("iCloud Sync", systemImage: storageIcon)
                        Spacer()
                        Text(storageDescription)
                            .foregroundStyle(PersistenceController.storageMode == .inMemory ? .red : .secondary)
                    }
                } header: {
                    Text("About")
                } footer: {
                    if PersistenceController.storageMode != .cloud {
                        Text(PersistenceController.storageMode == .inMemory
                            ? "The data store could not be opened. Changes made this session will not be saved."
                            : "iCloud is unavailable, so your data is stored on this device only.")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    /// Local telemetry only (WaitTimeRecord / DowntimeRecord live in the non-synced store)
    private func clearWaitHistory() {
        try? context.delete(model: WaitTimeRecord.self)
        try? context.delete(model: DowntimeRecord.self)
        try? context.save()
    }

    private func resetDiningHistory() {
        let restaurants = (try? context.fetch(FetchDescriptor<BucketRestaurant>())) ?? []
        for r in restaurants {
            r.isVisited = false
            r.visitDate = nil
            r.mattRating = 0
            r.wifeRating = 0
        }
        try? context.save()
    }
}

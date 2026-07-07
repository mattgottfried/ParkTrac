import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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

                // MARK: Resort
                Section {
                    HStack {
                        Label("Current Resort", systemImage: appState.selectedResort == .disney
                              ? "castle.fill" : "globe.americas.fill")
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
}

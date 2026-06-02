import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    private let store = StoreService.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
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

                // MARK: Remove Ads
                Section {
                    if store.isAdFree {
                        Label("Ads Removed — Thank You!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            HStack {
                                Label("Remove Ads", systemImage: "rectangle.slash")
                                Spacer()
                                if store.isPurchasing {
                                    ProgressView()
                                } else if let product = store.removeAdsProduct {
                                    Text(product.displayPrice)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Loading…")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                        .disabled(store.isPurchasing)

                        Button("Restore Purchase") {
                            Task { await store.restorePurchases() }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)

                        if let error = store.purchaseError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Support ParkTrac")
                } footer: {
                    Text(store.isAdFree
                        ? "Enjoy an ad-free experience."
                        : "One-time purchase to remove all ads and support development.")
                        .font(.caption)
                }

                // MARK: About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await store.loadProducts() }
        }
    }
}

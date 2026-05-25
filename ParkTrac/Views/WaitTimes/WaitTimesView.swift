import SwiftUI

struct WaitTimesView: View {
    @State private var viewModel = WaitTimesViewModel()
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Resort", selection: $viewModel.selectedGroup) {
                    ForEach(ParkGroup.allCases) { group in
                        Text(group.rawValue).tag(group)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.selectedGroup.parks) { park in
                            Button(park.name) {
                                viewModel.selectedPark = park
                            }
                            .buttonStyle(.bordered)
                            .tint(viewModel.selectedPark.id == park.id ? .blue : .secondary)
                            .fontWeight(viewModel.selectedPark.id == park.id ? .semibold : .regular)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 4)

                if viewModel.isLoading && viewModel.rides.isEmpty {
                    Spacer()
                    ProgressView("Loading rides…")
                    Spacer()
                } else if viewModel.filteredRides.isEmpty && !viewModel.isLoading {
                    Spacer()
                    ContentUnavailableView(
                        "No Rides Found",
                        systemImage: "magnifyingglass",
                        description: Text(viewModel.searchText.isEmpty
                            ? "No attraction data available."
                            : "No rides match \"\(viewModel.searchText)\".")
                    )
                    Spacer()
                } else {
                    List(viewModel.filteredRides) { entry in
                        RideRowView(entry: entry)
                    }
                    .listStyle(.plain)
                    .refreshable { await viewModel.loadRides() }
                }
            }
            .navigationTitle("Wait Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Wait Times").font(.headline)
                        if let refreshed = viewModel.lastRefreshed {
                            Text("Updated \(refreshed, style: .relative) ago")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search rides")
            .alert("Error Loading Rides", isPresented: $showError) {
                Button("Retry") { Task { await viewModel.loadRides() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                showError = newValue != nil
            }
        }
        .task {
            await viewModel.loadRides()
            viewModel.startAutoRefresh()
        }
        .onDisappear { viewModel.stopAutoRefresh() }
    }
}

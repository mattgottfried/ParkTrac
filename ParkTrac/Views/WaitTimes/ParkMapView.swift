import SwiftUI
import MapKit

struct ParkMapView: View {
    @State private var viewModel = WaitTimesViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRide: DisplayRide?
    @State private var sheetDetent: PresentationDetent = .fraction(0.35)

    var theme: ParkTheme { viewModel.selectedGroup.theme }

    var body: some View {
        ZStack(alignment: .top) {
            // Full-screen map
            Map(position: $cameraPosition) {
                ForEach(viewModel.ridesWithLocation) { ride in
                    Annotation(ride.name, coordinate: ride.coordinate!, anchor: .bottom) {
                        WaitTimeAnnotation(
                            ride: ride,
                            theme: theme,
                            selectedRide: $selectedRide
                        )
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            // Resort + park picker overlay at top
            VStack(spacing: 8) {
                Picker("Resort", selection: $viewModel.selectedGroup) {
                    ForEach(ParkGroup.allCases) { group in
                        Text(group.rawValue).tag(group)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .background(.ultraThinMaterial)

                if !viewModel.currentParks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.currentParks) { park in
                                Button(park.name) {
                                    viewModel.selectedPark = park
                                    if let coord = park.coordinate {
                                        withAnimation {
                                            cameraPosition = .region(MKCoordinateRegion(
                                                center: coord,
                                                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                                            ))
                                        }
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(viewModel.selectedPark?.id == park.id
                                    ? theme.annotationTextColor : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.selectedPark?.id == park.id
                                    ? theme.primaryColor : Color(.systemBackground).opacity(0.85))
                                .clipShape(Capsule())
                                .shadow(radius: 1)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.top, 8)
        }
        .sheet(isPresented: .constant(true)) {
            rideListSheet
        }
        .sheet(item: $selectedRide) { ride in
            RideDetailSheet(ride: ride, theme: theme, parkGroup: viewModel.selectedGroup)
        }
        .task {
            await viewModel.loadAllParks()
            viewModel.startAutoRefresh()
        }
        .onDisappear { viewModel.stopAutoRefresh() }
        .onChange(of: viewModel.selectedPark) { _, park in
            guard let coord = park?.coordinate else { return }
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                ))
            }
        }
    }

    // MARK: - Bottom Sheet

    private var rideListSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sheet handle
                Capsule()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedPark?.name ?? "Select a Park")
                            .font(.headline)
                        if let refreshed = viewModel.lastRefreshed {
                            Text("Updated \(refreshed, style: .relative) ago")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                if viewModel.isLoadingParks || (viewModel.isLoading && viewModel.rides.isEmpty) {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredRides.isEmpty {
                    ContentUnavailableView(
                        "No Rides",
                        systemImage: "figure.walk",
                        description: Text(viewModel.searchText.isEmpty
                            ? "Select a park to see wait times."
                            : "No rides match \"\(viewModel.searchText)\".")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.filteredRides) { ride in
                                RideCardView(ride: ride, theme: theme)
                                    .onTapGesture { selectedRide = ride }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .refreshable { await viewModel.refresh() }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search rides")
        }
        .presentationDetents([.fraction(0.15), .fraction(0.35), .large], selection: $sheetDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .large))
        .interactiveDismissDisabled()
        .presentationDragIndicator(.hidden)
    }
}

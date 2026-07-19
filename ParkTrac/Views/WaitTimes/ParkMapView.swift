import SwiftUI
import MapKit
import SwiftData

// MARK: - Ride Annotation Model

final class RidePointAnnotation: MKPointAnnotation {
    let ride: DisplayRide
    init(ride: DisplayRide) {
        self.ride = ride
        super.init()
        coordinate = ride.coordinate!
        title = ride.name
    }
}

// MARK: - Custom UIKit Annotation View

final class RideAnnotationView: MKAnnotationView {
    static let reuseID = "RideAnnotationView"

    private let bubble = UIView()
    private let label  = UILabel()
    private let pointer = UIView()

    var onTap: (() -> Void)?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        isOpaque = false
        backgroundColor = .clear
        centerOffset = CGPoint(x: 0, y: -22)

        bubble.layer.cornerRadius = 10
        bubble.layer.shadowColor  = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.25
        bubble.layer.shadowRadius  = 3
        bubble.layer.shadowOffset  = CGSize(width: 0, height: 2)
        addSubview(bubble)

        label.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        bubble.addSubview(label)

        // Small triangle pointer at bottom
        pointer.backgroundColor = .clear
        addSubview(pointer)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    func configure(ride: DisplayRide, theme: ParkTheme) {
        let bg: UIColor
        let text: UIColor
        let labelText: String

        if ride.status == "DOWN" {
            bg = UIColor(red: 1, green: 0.55, blue: 0, alpha: 1)
            text = .white
            labelText = "⚠"
        } else if !ride.isOperating {
            bg = UIColor.systemGray
            text = .white
            labelText = "✕"
        } else if let m = ride.waitMinutes {
            if m < 30 {
                bg = UIColor.systemGreen
            } else if m < 60 {
                bg = UIColor(red: 1, green: 0.75, blue: 0, alpha: 1)
            } else {
                bg = UIColor.systemRed
            }
            text = .white
            labelText = "\(m)"
        } else {
            bg = UIColor.systemBlue
            text = .white
            labelText = "—"
        }

        bubble.backgroundColor = bg
        label.textColor = text
        label.text = labelText

        // Size
        let bubbleW: CGFloat = labelText.count <= 2 ? 40 : 48
        let bubbleH: CGFloat = 28
        bubble.frame = CGRect(x: 0, y: 0, width: bubbleW, height: bubbleH)
        label.frame   = bubble.bounds.insetBy(dx: 4, dy: 2)

        // Pointer triangle (drawn as a rotated square)
        pointer.frame = CGRect(x: bubbleW/2 - 5, y: bubbleH - 3, width: 10, height: 10)
        pointer.transform = CGAffineTransform(rotationAngle: .pi / 4)
        pointer.backgroundColor = bg
        pointer.layer.cornerRadius = 1

        frame = CGRect(x: 0, y: 0, width: bubbleW, height: bubbleH + 5)
        alpha = ride.isOperating ? 1.0 : 0.6
    }

    @objc private func tapped() { onTap?() }
}

// MARK: - Styled Map (UIViewRepresentable)

struct StyledMapUIView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var rides: [DisplayRide]
    var theme: ParkTheme
    var isSatellite: Bool
    var onSelectRide: (DisplayRide) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.register(RideAnnotationView.self, forAnnotationViewWithReuseIdentifier: RideAnnotationView.reuseID)
        context.coordinator.addTiles(to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Satellite toggle
        if isSatellite {
            if !context.coordinator.isSatellite {
                context.coordinator.isSatellite = true
                map.mapType = .hybridFlyover
                map.removeOverlays(map.overlays)
            }
        } else {
            if context.coordinator.isSatellite {
                context.coordinator.isSatellite = false
                map.mapType = .mutedStandard
                context.coordinator.addTiles(to: map)
            }
        }

        // Region (only if significantly different to avoid fighting user pans)
        if !context.coordinator.isUserInteracting {
            let cur = map.region
            let deltaLat = abs(cur.center.latitude  - region.center.latitude)
            let deltaLon = abs(cur.center.longitude - region.center.longitude)
            if deltaLat > 0.001 || deltaLon > 0.001 {
                map.setRegion(region, animated: true)
            }
        }

        // Sync annotations
        let existing = map.annotations.compactMap { $0 as? RidePointAnnotation }
        let existingIds = Set(existing.map(\.ride.id))
        let newIds = Set(rides.filter { $0.coordinate != nil }.map(\.id))

        map.removeAnnotations(existing.filter { !newIds.contains($0.ride.id) })
        map.addAnnotations(rides.filter { $0.coordinate != nil && !existingIds.contains($0.id) }
            .map { RidePointAnnotation(ride: $0) })

        // Refresh visible annotations for wait-time updates
        for ann in map.annotations {
            guard let ra = ann as? RidePointAnnotation,
                  let view = map.view(for: ann) as? RideAnnotationView,
                  let updated = rides.first(where: { $0.id == ra.ride.id }) else { continue }
            view.configure(ride: updated, theme: theme)
        }
    }

    // MARK: Coordinator
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: StyledMapUIView
        var isSatellite = false
        var isUserInteracting = false

        init(_ parent: StyledMapUIView) { self.parent = parent }

        func addTiles(to map: MKMapView) {
            map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
            // CartoDB Voyager — clean, nature-tinted, no API key required
            let tile = MKTileOverlay(urlTemplate:
                "https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png")
            tile.canReplaceMapContent = true
            map.addOverlay(tile, level: .aboveLabels)
        }

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ra = annotation as? RidePointAnnotation else { return nil }
            let view = map.dequeueReusableAnnotationView(withIdentifier: RideAnnotationView.reuseID, for: annotation) as! RideAnnotationView
            view.configure(ride: ra.ride, theme: parent.theme)
            view.onTap = { [weak self] in self?.parent.onSelectRide(ra.ride) }
            return view
        }

        // Track user pan/zoom so we don't override it
        func mapView(_ map: MKMapView, regionWillChangeAnimated animated: Bool) {
            if let view = map.subviews.first, view.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true {
                isUserInteracting = true
            }
        }
        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            isUserInteracting = false
            // Write the user's final position back into the binding so the next
            // updateUIView call doesn't see a drift and snap back.
            let r = map.region
            DispatchQueue.main.async { self.parent.region = r }
        }
    }
}

// MARK: - Main Park Map View

// MARK: - Show Tab enum
private enum BottomTab { case rides, shows }

struct ParkMapView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhaseValue
    @Environment(\.modelContext) private var modelContext
    @Environment(WaitTimesViewModel.self) private var viewModel
    @State private var locationService = LocationService()
    @State private var region: MKCoordinateRegion = ParkGroup.disney.defaultRegion
    @State private var selectedRide: DisplayRide?
    @State private var panelExpanded: Bool = false
    @State private var mapStyleIsHybrid: Bool = false
    @State private var lastAutoZoomedParkId: String? = nil
    @State private var showTab: BottomTab = .rides
    @State private var showMustDoOnly: Bool = false
    var theme: ParkTheme { viewModel.selectedGroup.theme }

    var body: some View {
        ZStack(alignment: .top) {
            StyledMapUIView(
                region: $region,
                rides: viewModel.ridesWithLocation,
                theme: theme,
                isSatellite: mapStyleIsHybrid,
                onSelectRide: { selectedRide = $0 }
            )
            .ignoresSafeArea()

            // Top overlay: satellite toggle + park chips
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        mapStyleIsHybrid.toggle()
                    } label: {
                        Image(systemName: mapStyleIsHybrid ? "map" : "globe.americas.fill")
                            .font(.system(size: 16, weight: .medium))
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal)

                if viewModel.isLoadingParks {
                    ProgressView().padding(.vertical, 4)
                } else if !viewModel.currentParks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button("All Parks") {
                                viewModel.filterPark = nil
                                showMustDoOnly = false
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.filterPark == nil && !showMustDoOnly
                                ? theme.annotationTextColor : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(viewModel.filterPark == nil && !showMustDoOnly
                                ? theme.primaryColor : Color(.systemBackground).opacity(0.85))
                            .clipShape(Capsule()).shadow(radius: 1)

                            Button {
                                showMustDoOnly.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showMustDoOnly ? "star.fill" : "star")
                                    Text("Must Do")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(showMustDoOnly ? theme.annotationTextColor : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(showMustDoOnly ? Color.yellow : Color(.systemBackground).opacity(0.85))
                            .clipShape(Capsule()).shadow(radius: 1)

                            ForEach(viewModel.currentParks) { park in
                                Button(park.name) {
                                    viewModel.filterPark = park
                                    if let coord = park.coordinate {
                                        withAnimation {
                                            region = MKCoordinateRegion(
                                                center: coord,
                                                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015))
                                        }
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(viewModel.filterPark?.id == park.id
                                    ? theme.annotationTextColor : .primary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(viewModel.filterPark?.id == park.id
                                    ? theme.primaryColor : Color(.systemBackground).opacity(0.85))
                                .clipShape(Capsule()).shadow(radius: 1)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer()
                    rideListPanel
                        .frame(height: panelExpanded ? geo.size.height * 0.82 : 320)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: panelExpanded)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task {
            mapStyleIsHybrid = appState.defaultMapIsSatellite
            viewModel.sortAlphabetical = appState.sortRidesAlphabetically
            viewModel.selectedGroup = appState.selectedResort
            region = appState.selectedResort.defaultRegion
            await viewModel.loadAllParks()
            viewModel.startAutoRefresh()
            locationService.requestAndStart()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
            locationService.stop()
        }
        .onChange(of: scenePhaseValue) { _, phase in
            if phase == .background { locationService.stop() }
            else if phase == .active { locationService.requestAndStart() }
        }
        .onChange(of: appState.selectedResort) { _, resort in
            viewModel.selectedGroup = resort
            lastAutoZoomedParkId = nil
            withAnimation { region = resort.defaultRegion }
        }
        .onChange(of: viewModel.selectedGroup) { _, group in
            withAnimation { region = group.defaultRegion }
        }
        .onChange(of: appState.sortRidesAlphabetically) { _, val in viewModel.sortAlphabetical = val }
        .onChange(of: appState.defaultMapIsSatellite)   { _, val in mapStyleIsHybrid = val }
        .onChange(of: locationService.userCoordinate?.latitude) { _, _ in autoZoomIfInsidePark() }
        .onChange(of: viewModel.currentParks) { _, _ in autoZoomIfInsidePark() }
        .onChange(of: region.center.latitude) { _, _ in autoSelectParkFromRegion() }
        .onChange(of: region.center.longitude) { _, _ in autoSelectParkFromRegion() }
        .onChange(of: viewModel.lastRefreshed) { _, _ in
            NotificationService.shared.checkAlerts(rides: viewModel.allRides, context: modelContext)
            WaitTimeRecorder.shared.record(rides: viewModel.allRides, context: modelContext)
        }
        .sheet(item: $selectedRide) { ride in
            let parkName = viewModel.currentParks.first(where: { $0.id == ride.parkId })?.name ?? ""
            RideDetailSheet(ride: ride, theme: theme, parkGroup: viewModel.selectedGroup, parkName: parkName)
        }
    }

    // MARK: - Zoom-Based Auto-Select

    /// When the user pans/zooms so the map center is over a park and the zoom
    /// is close enough, automatically select that park's chip.
    private func autoSelectParkFromRegion() {
        // Only trigger when zoomed in close enough
        guard region.span.latitudeDelta < 0.05 else {
            // Zoomed out — clear park filter if it was set by this mechanism
            // (Don't clear if the user explicitly tapped a chip)
            return
        }
        let center = CLLocation(latitude: region.center.latitude,
                                longitude: region.center.longitude)
        let nearest = viewModel.currentParks
            .compactMap { park -> (ParkEntity, CLLocationDistance)? in
                guard let coord = park.coordinate else { return nil }
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                let dist = center.distance(from: loc)
                return dist < 3000 ? (park, dist) : nil
            }
            .min { $0.1 < $1.1 }?.0
        guard let park = nearest, viewModel.filterPark?.id != park.id else { return }
        viewModel.filterPark = park
    }

    // MARK: - GPS Auto-Zoom

    private func autoZoomIfInsidePark() {
        guard let nearest = locationService.nearestPark(from: viewModel.currentParks) else { return }
        guard nearest.id != lastAutoZoomedParkId else { return }
        lastAutoZoomedParkId = nearest.id
        viewModel.filterPark = nearest
        if let coord = nearest.coordinate {
            withAnimation {
                region = MKCoordinateRegion(center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012))
            }
        }
    }

    // MARK: - Bottom Panel

    private var panelHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(viewModel.filterPark?.name ?? viewModel.selectedGroup.rawValue)
                        .font(.headline)
                    if let level = viewModel.currentCrowdLevel {
                        Label(level.rawValue, systemImage: level.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(level.color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(level.color.opacity(0.12), in: Capsule())
                    }
                }
                if let avg = viewModel.currentAverageWait {
                    let parkName = viewModel.filterPark?.name ?? viewModel.currentParks.first?.name ?? ""
                    let parkId   = viewModel.filterPark?.id  ?? viewModel.currentParks.first?.id  ?? ""
                    ParkComparisonView(parkName: parkName, parkId: parkId, currentAvgWait: avg)
                }
                if let refreshed = viewModel.lastRefreshed {
                    Text("Updated \(refreshed, style: .relative) ago")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.isLoading { ProgressView() }
        }
        .padding(.horizontal).padding(.bottom, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 14))
            TextField("Search rides", text: Bindable(viewModel).searchText)
                .font(.subheadline).autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal).padding(.top, 4).padding(.bottom, 6)
    }

    private var displayedRides: [DisplayRide] {
        viewModel.filteredRides.filter { ride in
            !showMustDoOnly || appState.wishList.contains(ride.id)
        }
    }

    private var rideListPanel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8).padding(.bottom, 6)
                .onTapGesture { panelExpanded.toggle() }
                .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                    if v.translation.height < -30 { panelExpanded = true }
                    else if v.translation.height > 30 { panelExpanded = false }
                })

            panelHeader

            // Park Hours Header
            if let park = viewModel.filterPark ?? viewModel.currentParks.first {
                ParkHoursHeaderView(
                    park: park,
                    schedule: viewModel.todaySchedule(for: park),
                    theme: theme
                )
                .padding(.horizontal)
            }

            // Rides / Shows segmented control
            Picker("Tab", selection: $showTab) {
                Text("Rides").tag(BottomTab.rides)
                Text("Shows").tag(BottomTab.shows)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 4)

            if showTab == .rides {
                searchBar
            }

            Divider()

            if showTab == .shows {
                ShowsListView(shows: viewModel.currentShows, theme: theme)
            } else if viewModel.isLoadingParks || (viewModel.isLoading && viewModel.allRides.isEmpty) {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(errorMsg).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await viewModel.retry() } }.buttonStyle(.borderedProminent)
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedRides.isEmpty {
                ContentUnavailableView(
                    showMustDoOnly ? "No Must-Do Rides" : "No Rides",
                    systemImage: showMustDoOnly ? "star" : "figure.walk",
                    description: Text(showMustDoOnly
                        ? "Star rides in their detail page to add to your Must-Do list."
                        : (viewModel.searchText.isEmpty ? "Loading wait times…" : "No rides match \"\(viewModel.searchText)\"."))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedRides) { ride in
                            RideCardView(ride: ride, theme: theme)
                                .onTapGesture { selectedRide = ride }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                .refreshable { await viewModel.refresh() }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: -2)
    }
}

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

/// Where you parked (ParkingService). Tapping it opens the parking sheet.
final class ParkingPointAnnotation: MKPointAnnotation {}

// MARK: - Map focus (which park the list follows)

/// Zoomed out → all parks; zoomed in near a park → that park; in between → keep what's showing
/// (so the list doesn't flicker while zooming). Pure, unit tested.
/// Bottom panel drag: follows the finger, then snaps open/closed from where it was
/// dropped or how hard it was flicked.
enum PanelDrag {
    /// A drag or flick of at least this many points switches state.
    static let threshold: CGFloat = 60

    static func shouldExpand(wasExpanded: Bool, translation: CGFloat, predicted: CGFloat) -> Bool {
        let move = abs(predicted) > abs(translation) ? predicted : translation
        if move <= -threshold { return true }
        if move >= threshold { return false }
        return wasExpanded
    }

    /// Panel height while dragging (dragging up = negative translation = taller), kept on screen.
    static func height(expanded: Bool, drag: CGFloat, collapsed: CGFloat, full: CGFloat) -> CGFloat {
        let base = expanded ? full : collapsed
        return min(max(base - drag, collapsed * 0.6), full)
    }
}

enum MapFocus: Equatable {
    case allParks
    case park(String)
    case keep

    static let allParksSpan = 0.05
    static let parkSpan = 0.035
    static let maxParkDistance: CLLocationDistance = 3000

    static func decide(span: Double, center: CLLocationCoordinate2D,
                       parks: [(id: String, coordinate: CLLocationCoordinate2D)]) -> MapFocus {
        if span >= allParksSpan { return .allParks }
        guard span <= parkSpan else { return .keep }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let nearest = parks
            .map { (id: $0.id, distance: here.distance(from: CLLocation(latitude: $0.coordinate.latitude,
                                                                          longitude: $0.coordinate.longitude))) }
            .filter { $0.distance <= maxParkDistance }
            .min { $0.distance < $1.distance }
        // Zoomed in somewhere that isn't a park (Disney Springs, CityWalk) → whole resort
        return nearest.map { .park($0.id) } ?? .allParks
    }
}

// MARK: - Custom UIKit Annotation View

final class RideAnnotationView: MKAnnotationView, UIContextMenuInteractionDelegate {
    static let reuseID = "RideAnnotationView"

    private let bubble = UIView()
    private let label  = UILabel()
    private let pointer = UIView()

    var onTap: (() -> Void)?
    /// Long-press menu (same actions as the ride card's context menu), built on demand
    var menuProvider: (() -> UIMenu?)?
    /// Last configuration, so a Dynamic Type change can re-lay out the pin.
    private var current: (ride: DisplayRide, theme: ParkTheme)?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: RideAnnotationView, _: UITraitCollection) in
            if let current = view.current { view.configure(ride: current.ride, theme: current.theme) }
        }
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
        addInteraction(UIContextMenuInteraction(delegate: self))

        // VoiceOver: the pin is one button; label/value are set in configure()
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Shows wait predictions and details"
    }

    func configure(ride: DisplayRide, theme: ParkTheme) {
        current = (ride, theme)
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

        // Size — the number follows Dynamic Type (capped so pins don't swallow the map)
        let font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: .systemFont(ofSize: 13, weight: .bold), maximumPointSize: 22)
        label.font = font
        let textWidth = ceil((labelText as NSString).size(withAttributes: [.font: font]).width)
        let bubbleW = max(40, textWidth + 16)
        let bubbleH = max(28, ceil(font.lineHeight) + 10)
        bubble.frame = CGRect(x: 0, y: 0, width: bubbleW, height: bubbleH)
        label.frame   = bubble.bounds.insetBy(dx: 4, dy: 2)
        centerOffset = CGPoint(x: 0, y: -(bubbleH + 5) / 2 - 5)

        // Pointer triangle (drawn as a rotated square). Reset the transform before
        // setting the frame — frame is undefined while a rotation is applied.
        pointer.transform = .identity
        pointer.frame = CGRect(x: bubbleW/2 - 5, y: bubbleH - 3, width: 10, height: 10)
        pointer.transform = CGAffineTransform(rotationAngle: .pi / 4)
        pointer.backgroundColor = bg
        pointer.layer.cornerRadius = 1

        frame = CGRect(x: 0, y: 0, width: bubbleW, height: bubbleH + 5)
        alpha = ride.isOperating ? 1.0 : 0.6

        accessibilityLabel = ride.name
        accessibilityValue = ride.spokenStatus
    }

    @objc private func tapped() { onTap?() }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard menuProvider != nil else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.menuProvider?()
        }
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }
}

// MARK: - Styled Map (UIViewRepresentable)

struct StyledMapUIView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var rides: [DisplayRide]
    var theme: ParkTheme
    var isSatellite: Bool
    var onSelectRide: (DisplayRide) -> Void
    var makeMenu: (DisplayRide) -> UIMenu? = { _ in nil }
    /// Today's car spot at this resort, shown as a car pin
    var parkingSpot: ParkingSpot? = nil
    var onSelectParking: () -> Void = {}
    /// Bumped by the "my location" button: center on the blue dot (MapKit's precise fix)
    var recenterRequest: Int = 0
    /// Called when the map has no fix yet, so the caller can fall back to its own location
    var onRecenterWithoutFix: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.register(RideAnnotationView.self, forAnnotationViewWithReuseIdentifier: RideAnnotationView.reuseID)
        map.preferredConfiguration = Self.configuration(satellite: isSatellite)
        context.coordinator.isSatellite = isSatellite
        context.coordinator.lastRecenterRequest = recenterRequest
        return map
    }

    /// Apple Maps base layer (no API key). Muted standard keeps the colored wait pins
    /// prominent; Apple's own attraction labels are filtered out so they don't clash
    /// with the ride pins, but restrooms and food stay visible.
    static func configuration(satellite: Bool) -> MKMapConfiguration {
        let poiFilter = MKPointOfInterestFilter(including: [.restroom, .restaurant, .cafe, .parking])
        if satellite {
            let config = MKHybridMapConfiguration(elevationStyle: .realistic)
            config.pointOfInterestFilter = poiFilter
            return config
        }
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = poiFilter
        return config
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Satellite toggle
        if isSatellite != context.coordinator.isSatellite {
            context.coordinator.isSatellite = isSatellite
            map.preferredConfiguration = Self.configuration(satellite: isSatellite)
        }

        // "My location" button: center on the blue dot at street level, then write the region
        // back so the sync below doesn't snap it away
        var recentered = false
        if recenterRequest != context.coordinator.lastRecenterRequest {
            context.coordinator.lastRecenterRequest = recenterRequest
            if let fix = map.userLocation.location, CLLocationCoordinate2DIsValid(fix.coordinate) {
                let r = MKCoordinateRegion(center: fix.coordinate,
                                           span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))
                map.setRegion(r, animated: true)
                DispatchQueue.main.async { self.region = r }
                recentered = true
            } else {
                DispatchQueue.main.async { onRecenterWithoutFix() }
            }
        }

        // Region (only if significantly different to avoid fighting user pans)
        if !recentered && !context.coordinator.isUserInteracting {
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

        // Car pin: replace when the spot moves or is cleared
        let oldCar = map.annotations.compactMap { $0 as? ParkingPointAnnotation }
        let newCoord = parkingSpot?.coordinate
        let carUnchanged = oldCar.count == 1 && newCoord.map {
            oldCar[0].coordinate.latitude == $0.latitude && oldCar[0].coordinate.longitude == $0.longitude
                && oldCar[0].title == parkingSpot?.title
        } == true
        if !carUnchanged {
            map.removeAnnotations(oldCar)
            if let newCoord, let spot = parkingSpot {
                let car = ParkingPointAnnotation()
                car.coordinate = newCoord
                car.title = spot.title
                map.addAnnotation(car)
            }
        }

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
        var lastRecenterRequest = 0

        init(_ parent: StyledMapUIView) { self.parent = parent }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is ParkingPointAnnotation {
                let id = "ParkingPin"
                let view = map.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.glyphImage = UIImage(systemName: "car.fill")
                view.markerTintColor = .systemBlue
                view.displayPriority = .required
                view.titleVisibility = .visible
                view.accessibilityLabel = "Your car"
                return view
            }
            guard let ra = annotation as? RidePointAnnotation else { return nil }
            let view = map.dequeueReusableAnnotationView(withIdentifier: RideAnnotationView.reuseID, for: annotation) as! RideAnnotationView
            view.configure(ride: ra.ride, theme: parent.theme)
            view.onTap = { [weak self] in self?.parent.onSelectRide(ra.ride) }
            view.menuProvider = { [weak self] in self?.parent.makeMenu(ra.ride) }
            return view
        }

        func mapView(_ map: MKMapView, didSelect annotation: MKAnnotation) {
            guard annotation is ParkingPointAnnotation else { return }
            map.deselectAnnotation(annotation, animated: false)
            parent.onSelectParking()
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
private enum BottomTab: String { case rides, shows }

/// Sheets opened from a ride card's long-press menu.
private enum RideMenuAction: Identifiable {
    case addToPlan(DisplayRide)
    case alert(DisplayRide)

    var id: String {
        switch self {
        case .addToPlan(let ride): return "plan-\(ride.id)"
        case .alert(let ride):     return "alert-\(ride.id)"
        }
    }
}

struct ParkMapView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhaseValue
    @Environment(\.modelContext) private var modelContext
    @Environment(WaitTimesViewModel.self) private var viewModel
    @Query(sort: \RideLog.riddenAt) private var allRideLogs: [RideLog]
    @State private var showParkBingo = false
    @State private var locationService = LocationService()
    @State private var recenterRequest = 0
    @State private var showLocationDenied = false
    @State private var region: MKCoordinateRegion = ParkGroup.disney.defaultRegion
    @State private var selectedRide: DisplayRide?
    @State private var panelExpanded: Bool = false
    /// Live finger offset while dragging the panel header (springs back to 0 on release)
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.8)))
    private var panelDrag: CGFloat = 0
    @State private var mapStyleIsHybrid: Bool = false
    @State private var lastAutoZoomedParkId: String? = nil
    @AppStorage("waitTimesBottomTab") private var showTab: BottomTab = .rides
    @State private var showMustDoOnly: Bool = false
    @AppStorage("rideSort") private var rideSort: RideSort = .longestWait
    @AppStorage("hideClosedRides") private var hideClosed: Bool = false
    @AppStorage("singleRiderOnly") private var singleRiderOnly: Bool = false
    /// 0 = no limit
    @AppStorage("maxWaitFilter") private var maxWait: Int = 0
    @State private var rideAction: RideMenuAction?
    @State private var showTipBoard = false
    @State private var showRestStop = false
    /// Bumped only when the user taps to refresh, so the success haptic doesn't fire on the 60s auto-refresh.
    @State private var userRefreshCount = 0
    /// Status per ride from the previous refresh, to spot rides that just went DOWN
    @State private var lastStatuses: [String: String] = [:]
    /// Bumped when a Must-Do ride goes DOWN → warning haptic
    @State private var mustDoDownCount = 0
    /// "<parkId>-<openingTime>" of the rope-drop activity we last started —
    /// prevents the 60s auto-refresh from restarting it every cycle.
    @State private var lastRopeDropKey: String? = nil

    var theme: ParkTheme { viewModel.selectedGroup.theme }

    var body: some View {
        ZStack(alignment: .top) {
            StyledMapUIView(
                region: $region,
                rides: viewModel.ridesWithLocation,
                theme: theme,
                isSatellite: mapStyleIsHybrid,
                onSelectRide: { selectedRide = $0 },
                makeMenu: { pinMenu(for: $0) },
                parkingSpot: ParkingService.shared.spot(for: appState.selectedResort),
                onSelectParking: { DeepLinkRouter.shared.open(.parking) },
                recenterRequest: recenterRequest,
                onRecenterWithoutFix: recenterFromLocationService
            )
            .ignoresSafeArea()

            // Top overlay: satellite toggle + park chips
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        mapStyleIsHybrid.toggle()
                    } label: {
                        Image(systemName: mapStyleIsHybrid ? "map" : "globe.americas.fill")
                            .font(.body.weight(.medium))
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(mapStyleIsHybrid ? "Show standard map" : "Show satellite map")
                    Spacer()
                    // Tip Board: Must-Dos with best time today
                    Button {
                        showTipBoard = true
                    } label: {
                        Image(systemName: "list.star")
                            .font(.body.weight(.medium))
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Tip Board")
                    // Rest stop: somewhere indoor and seated, no standby line
                    Button {
                        showRestStop = true
                    } label: {
                        Image(systemName: "figure.seated.side.air.distribution")
                            .font(.body.weight(.medium))
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Find a rest stop")
                    // Car locator
                    let parked = ParkingService.shared.spot(for: appState.selectedResort) != nil
                    Button {
                        DeepLinkRouter.shared.open(.parking)
                    } label: {
                        Image(systemName: parked ? "car.fill" : "car")
                            .font(.body.weight(.medium))
                            .foregroundStyle(parked ? Color.blue : Color.primary)
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(parked ? "Find my car" : "Save parking spot")
                    // Recenter on my location
                    Button {
                        recenterOnMe()
                    } label: {
                        Image(systemName: locationAllowed ? "location.fill" : "location")
                            .font(.body.weight(.medium))
                            .foregroundStyle(locationAllowed ? Color.blue : Color.primary)
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Show my location")
                }
                .padding(.horizontal)

                if viewModel.isLoadingParks {
                    ProgressView().padding(.vertical, 4)
                } else if !viewModel.currentParks.isEmpty {
                    HStack(spacing: 8) {
                        // Park: follows the map as you zoom; pick one to fly there
                        Menu {
                            Button {
                                viewModel.filterPark = nil
                                withAnimation { region = viewModel.selectedGroup.defaultRegion }
                            } label: {
                                if viewModel.filterPark == nil { Label("All Parks", systemImage: "checkmark") }
                                else { Text("All Parks") }
                            }
                            ForEach(viewModel.currentParks) { park in
                                Button {
                                    viewModel.filterPark = park
                                    if let coord = park.coordinate {
                                        withAnimation {
                                            region = MKCoordinateRegion(
                                                center: coord,
                                                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015))
                                        }
                                    }
                                } label: {
                                    if viewModel.filterPark?.id == park.id { Label(park.name, systemImage: "checkmark") }
                                    else { Text(park.name) }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(viewModel.filterPark?.name ?? "All Parks")
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        }
                        .accessibilityLabel("Park: \(viewModel.filterPark?.name ?? "All Parks")")
                        .accessibilityHint("Choose a park. It also changes as you zoom the map.")

                        // Must-Do only
                        Button {
                            showMustDoOnly.toggle()
                        } label: {
                            Image(systemName: showMustDoOnly ? "star.fill" : "star")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(showMustDoOnly ? Color.yellow : Color.primary)
                                .padding(9)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        }
                        .accessibilityLabel(showMustDoOnly ? "Showing Must-Dos only" : "Show Must-Dos only")
                        .accessibilityAddTraits(showMustDoOnly ? .isSelected : [])

                        Spacer()
                    }
                    .padding(.horizontal)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
            }
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer()
                    rideListPanel
                        .frame(height: PanelDrag.height(expanded: panelExpanded, drag: panelDrag,
                                                        collapsed: 320, full: geo.size.height * 0.82))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: panelExpanded)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task {
            mapStyleIsHybrid = appState.defaultMapIsSatellite
            if appState.sortRidesAlphabetically != (rideSort == .name) {
                rideSort = appState.sortRidesAlphabetically ? .name : .longestWait
            }
            viewModel.rideSort = rideSort
            viewModel.selectedGroup = appState.selectedResort
            region = appState.selectedResort.defaultRegion
            await viewModel.loadAllParks()
            viewModel.startAutoRefresh()
            locationService.requestAndStart()
            syncRopeDropActivity()
        }
        .onDisappear {
            // Keep refreshing on other tabs while a Lightning Lane or reopen watch is running
            if !LightningLaneWatchService.shared.hasActiveWatches
                && !ReopenWatchService.shared.watches.contains(where: \.isToday) {
                viewModel.stopAutoRefresh()
            }
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
        // Settings' A–Z toggle and the list's sort menu mirror each other
        .onChange(of: appState.sortRidesAlphabetically) { _, val in
            if val != (rideSort == .name) { rideSort = val ? .name : .longestWait }
        }
        .onChange(of: rideSort) { _, sort in
            viewModel.rideSort = sort
            if appState.sortRidesAlphabetically != (sort == .name) {
                appState.sortRidesAlphabetically = (sort == .name)
            }
        }
        .onChange(of: appState.defaultMapIsSatellite)   { _, val in mapStyleIsHybrid = val }
        .onChange(of: locationService.userCoordinate?.latitude) { _, _ in autoZoomIfInsidePark() }
        .onChange(of: viewModel.currentParks) { _, _ in autoZoomIfInsidePark() }
        .onChange(of: region.center.latitude) { _, _ in autoSelectParkFromRegion() }
        .onChange(of: region.center.longitude) { _, _ in autoSelectParkFromRegion() }
        .onChange(of: region.span.latitudeDelta) { _, _ in autoSelectParkFromRegion() }
        .onChange(of: DeepLinkRouter.shared.pendingRideId, initial: true) { _, _ in openPendingRide() }
        .onChange(of: DeepLinkRouter.shared.waitTimesReselectCount) { _, _ in
            // Tab tapped again: back to the whole resort (or the selected park)
            if let coord = viewModel.filterPark?.coordinate {
                withAnimation {
                    region = MKCoordinateRegion(center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015))
                }
            } else {
                withAnimation { region = viewModel.selectedGroup.defaultRegion }
            }
        }
        .onChange(of: viewModel.lastRefreshed) { _, _ in
            openPendingRide()
            noteMustDoDowntime()
            NotificationService.shared.checkAlerts(
                rides: viewModel.allRides, context: modelContext, resort: viewModel.selectedGroup,
                parkNames: Dictionary(viewModel.currentParks.map { ($0.id, $0.name) },
                                      uniquingKeysWith: { first, _ in first }))
            WaitTimeRecorder.shared.record(rides: viewModel.allRides, context: modelContext)
            GoodTimeService.shared.update(rides: viewModel.allRides, mustDo: appState.wishList, context: modelContext)
            // Must-Do down / back-up alerts (server pushes when Instant Alerts is on)
            MustDoDownService.shared.update(rides: viewModel.allRides, mustDo: appState.wishList,
                                            resort: viewModel.selectedGroup,
                                            parkName: { id in viewModel.currentParks.first { $0.id == id }?.name ?? "" })
            // Community wait history (server) — once per park per day
            let historyParks = viewModel.currentParks.map(\.id)
            let historyZone = viewModel.selectedGroup.timeZone
            Task { await CommunityHistoryService.shared.refreshIfNeeded(parkIds: historyParks, timeZone: historyZone) }
            // Rain plan: hourly rain chance (≤ every 30 min) + the once-a-day heads-up
            let rainResort = viewModel.selectedGroup
            Task { await RainForecastService.shared.refreshIfNeeded(resort: rainResort) }
            // Today's plan re-plans from here and now
            ItineraryService.shared.replan(viewModel: viewModel, resort: viewModel.selectedGroup,
                                           location: locationService.userCoordinate, context: modelContext)
            syncRopeDropActivity()
            // Schedules may have just loaded — (re)arm the "parks close soon" car reminder
            ParkingReminder.refresh(resort: viewModel.selectedGroup,
                                    schedule: viewModel.todaySchedule(forResort: viewModel.selectedGroup))
        }
        .alert("Location Is Off", isPresented: $showLocationDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow ThrillTrack to use your location in Settings to see where you are on the map.")
        }
        .sheet(isPresented: $showTipBoard) {
            TipBoardView()
        }
        .sheet(isPresented: $showParkBingo) {
            if let park = viewModel.filterPark, let bingo = parkBingo {
                ParkBingoSheet(parkName: park.name, ridden: bingo.ridden, remaining: bingo.remaining)
            }
        }
        .alert("Need a Break?", isPresented: $showRestStop) {
            Button("OK") {}
        } message: {
            Text(restStopSuggestion.map(RestStopSuggestion.text)
                 ?? "No indoor rest spot found right now — check back after the next refresh.")
        }
        .sheet(item: $rideAction) { action in
            switch action {
            case .addToPlan(let ride):
                AddPlanItemView(resort: viewModel.selectedGroup.rawValue, prefillRide: ride,
                                prefillPark: parkName(for: ride))
            case .alert(let ride):
                SetAlertSheet(ride: ride)
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.filterPark?.id)
        .sensoryFeedback(.selection, trigger: showMustDoOnly)
        .sensoryFeedback(.selection, trigger: showTab)
        .sensoryFeedback(.success, trigger: userRefreshCount)
        .sensoryFeedback(.warning, trigger: mustDoDownCount)
        .sheet(item: $selectedRide) { ride in
            let parkName = viewModel.currentParks.first(where: { $0.id == ride.parkId })?.name ?? ""
            RideDetailSheet(ride: ride, theme: theme, parkGroup: viewModel.selectedGroup, parkName: parkName)
        }
    }

    // MARK: - Walking time

    private func walkMinutes(to ride: DisplayRide) -> Int? {
        guard let me = locationService.userCoordinate, let there = ride.coordinate else { return nil }
        return WalkEstimate.minutes(from: me, to: there)
    }

    // MARK: - Must-Do downtime

    /// Warning haptic when a Must-Do ride flips to DOWN between refreshes (first load doesn't count).
    private func noteMustDoDowntime() {
        let wentDown = viewModel.allRides.contains { ride in
            guard ride.status == "DOWN", appState.wishList.contains(ride.id),
                  let previous = lastStatuses[ride.id] else { return false }
            return previous != "DOWN"
        }
        lastStatuses = Dictionary(viewModel.allRides.map { ($0.id, $0.status ?? "") },
                                  uniquingKeysWith: { first, _ in first })
        if wentDown { mustDoDownCount += 1 }
    }

    // MARK: - Deep Link

    /// Opens the ride sheet requested by a deep link / notification once the ride is loaded.
    private func openPendingRide() {
        let router = DeepLinkRouter.shared
        guard let id = router.pendingRideId else { return }
        if let ride = viewModel.allRides.first(where: { $0.id == id }) {
            router.pendingRideId = nil
            selectedRide = ride
        } else if viewModel.lastRefreshed != nil && !viewModel.isLoading {
            // Loaded and still not found (e.g. other resort) — drop it rather than pop up later
            router.pendingRideId = nil
        }
    }

    // MARK: - Rope Drop Live Activity

    /// Starts a park-opening (rope drop) countdown Live Activity for the
    /// currently selected park when its operating opening time is still in the
    /// future. Called from `.task` and every 60s refresh; a per-(park, day)
    /// key guards against restarting the activity on every refresh cycle.
    /// Once the opening passes, the activity is left to go stale naturally.
    private func syncRopeDropActivity() {
        guard let park = viewModel.filterPark ?? viewModel.currentParks.first else { return }
        let schedule = viewModel.todaySchedule(for: park)
        guard let operatingDay = schedule.first(where: { $0.type == "OPERATING" || $0.type == nil }),
              let opening = operatingDay.openingDate,
              opening > .now
        else { return }
        let key = "\(park.id)-\(opening.timeIntervalSince1970)"
        guard key != lastRopeDropKey else { return }
        lastRopeDropKey = key
        LiveActivityManager.startRopeDrop(parkName: park.name, openingTime: opening,
                                          resortRaw: viewModel.selectedGroup.rawValue)
    }

    // MARK: - Zoom-Based Auto-Select

    /// When the user pans/zooms so the map center is over a park and the zoom
    /// is close enough, automatically select that park's chip.
    /// The list (and hours bar) follow the map: zoomed out → all parks, zoomed into a park → that park.
    private func autoSelectParkFromRegion() {
        let parks = viewModel.currentParks.compactMap { park -> (id: String, coordinate: CLLocationCoordinate2D)? in
            park.coordinate.map { (id: park.id, coordinate: $0) }
        }
        switch MapFocus.decide(span: region.span.latitudeDelta, center: region.center, parks: parks) {
        case .allParks:
            if viewModel.filterPark != nil { viewModel.filterPark = nil }
        case .park(let id):
            if viewModel.filterPark?.id != id {
                viewModel.filterPark = viewModel.currentParks.first { $0.id == id }
            }
        case .keep:
            break
        }
    }

    // MARK: - GPS Auto-Zoom

    private var locationAllowed: Bool {
        locationService.authorizationStatus == .authorizedWhenInUse
            || locationService.authorizationStatus == .authorizedAlways
    }

    /// "My location" button: asks for permission if needed (or opens Settings if it was
    /// denied), otherwise centers the map on the blue dot.
    private func recenterOnMe() {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            showLocationDenied = true
        case .notDetermined:
            locationService.requestAndStart()
        default:
            recenterRequest += 1
        }
    }

    /// The map has no fix yet — use the location service's (coarser) one if there is one.
    private func recenterFromLocationService() {
        guard let me = locationService.userCoordinate else { return }
        withAnimation {
            region = MKCoordinateRegion(center: me,
                                        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))
        }
    }

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

    /// Minutes until rides start closing at the focused park, nil unless a single park is in
    /// focus and its close is within `ClosingSoon.leadMinutes`.
    private var closingSoonMinutes: Int? {
        guard let park = viewModel.filterPark else { return nil }
        return ClosingSoon.minutesUntilClose(schedule: viewModel.todaySchedule(for: park))
    }

    /// "Quietest around 9 AM, busiest around 2 PM" for the focused park, from community history.
    private var quietestHourText: String? {
        guard let park = viewModel.filterPark else { return nil }
        let schedule = viewModel.todaySchedule(for: park)
        guard let open = schedule.compactMap(\.openingDate).min(),
              let close = schedule.compactMap(\.closingDate).max() else { return nil }
        let cal = Calendar.current
        let openHour = cal.component(.hour, from: open)
        let closeHour = max(openHour, cal.component(.hour, from: close))
        let waits = viewModel.allRides
            .filter { $0.parkId == park.id }
            .map { CommunityHistoryService.shared.waitsByHour(rideId: $0.id, parkId: park.id) }
            .filter { !$0.isEmpty }
        guard let result = QuietestHour.compute(rideWaitsByHour: waits, openHours: openHour...closeHour) else { return nil }
        return QuietestHour.headline(quiet: result.quiet, busy: result.busy)
    }

    /// Somewhere indoor and seated right now — a show starting soon, else the shortest-wait
    /// indoor ride. Uses whichever parks are in scope (the focused park, or the whole resort).
    private var restStopSuggestion: RestStopSuggestion.Kind? {
        let now = Date()
        let shows = viewModel.currentShows.map { show -> (name: String, isOperating: Bool, startsInMinutes: Int?) in
            let minutes = show.nextShowtime.map { Int($0.timeIntervalSince(now) / 60) }
            return (show.name, show.isOperating, minutes)
        }
        let rides = viewModel.allRides
            .filter { viewModel.filterPark == nil || $0.parkId == viewModel.filterPark?.id }
            .map { (name: $0.name, isOperating: $0.isOperating, waitMinutes: $0.waitMinutes) }
        return RestStopSuggestion.pick(shows: shows, rides: rides, resort: viewModel.selectedGroup)
    }

    /// Ride names at the focused park ridden since the current trip started (not lifetime) —
    /// trips are inferred from gaps between logged days, same as Visit History.
    private var currentTripRiddenNames: Set<String> {
        guard let park = viewModel.filterPark else { return [] }
        let cal = Calendar.current
        let resortLogs = allRideLogs.filter { $0.resort == viewModel.selectedGroup.rawValue }
        var byDay: [Date: [RideLog]] = [:]
        for log in resortLogs { byDay[cal.startOfDay(for: log.riddenAt), default: []].append(log) }
        let visitDays = byDay.map { VisitDay(id: $0.key, resort: viewModel.selectedGroup.rawValue, entries: $0.value) }
        guard let trip = VisitTripGrouper.group(visitDays).last else { return [] }
        return Set(trip.days.flatMap { $0.entries.filter { $0.parkName == park.name }.map(\.rideName) })
    }

    private var parkBingo: (ridden: [String], remaining: [String])? {
        guard let park = viewModel.filterPark else { return nil }
        let roster = viewModel.rideRoster(for: park)
        guard !roster.isEmpty else { return nil }
        return ParkBingo.progress(roster: roster, riddenThisTrip: currentTripRiddenNames)
    }

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
                if let avg = viewModel.currentAverageWait, let park = viewModel.filterPark {
                    ParkComparisonView(parkName: park.name, parkId: park.id, currentAvgWait: avg)
                }
                if viewModel.isOffline {
                    Label("Offline — no live wait times", systemImage: "wifi.slash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.gray, in: Capsule())
                }
                if let minutes = closingSoonMinutes {
                    Label(minutes <= 1 ? "Rides closing very soon" : "Rides closing in about \(minutes) min",
                          systemImage: "clock.badge.exclamationmark.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange, in: Capsule())
                }
                if let quietestHourText {
                    Text(quietestHourText)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let bingo = parkBingo {
                    Button {
                        showParkBingo = true
                    } label: {
                        Label("Park Bingo: \(bingo.ridden.count) of \(bingo.ridden.count + bingo.remaining.count) this trip",
                              systemImage: "checklist")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                }
                if let refreshed = viewModel.lastRefreshed {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        let minutesOld = Int(ctx.date.timeIntervalSince(refreshed) / 60)
                        if minutesOld >= 5 {
                            // Wait times refresh on their own every minute; this is the manual nudge
                            Button {
                                Task {
                                    await viewModel.refresh()
                                    userRefreshCount += 1
                                }
                            } label: {
                                Label("Wait times from \(minutesOld) min ago — tap to refresh",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.orange, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Updated \(refreshed, style: .relative) ago")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
            if viewModel.isLoading { ProgressView() }
        }
        .padding(.horizontal).padding(.bottom, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.subheadline)
                    .accessibilityHidden(true)
                TextField("Search rides", text: Bindable(viewModel).searchText)
                    .font(.subheadline).autocorrectionDisabled()
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10))

            filterMenu
        }
        .padding(.horizontal).padding(.top, 4).padding(.bottom, 6)
    }

    /// List-only filters. Kept out of `viewModel.filteredRides` so crowd level / average wait
    /// still reflect the whole park.
    /// Rides whose wait is well below usual right now — Must-Dos first
    @ViewBuilder
    private var goodTimeStrip: some View {
        let picks = GoodTimeService.shared.ranked(rides: displayedRides, mustDo: appState.wishList)
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                    Text("Good Time to Ride").foregroundStyle(.primary)
                }
                .font(.subheadline.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(picks, id: \.ride.id) { pick in
                            Button { selectedRide = pick.ride } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 4) {
                                        if appState.wishList.contains(pick.ride.id) {
                                            Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                                        }
                                        Text(pick.ride.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(pick.deal.wait) min")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(.green)
                                        Text("usually \(pick.deal.usual.minutes)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 160, alignment: .leading)
                                .frame(minHeight: 78)
                                .padding(12)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.green.opacity(0.5), lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(pick.ride.name), \(pick.deal.wait) minutes, \(pick.deal.longText)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
        }
    }

    /// Shortest absolute waits right now — a ride doesn't need a long "usual" to belong here,
    /// just a short line, so this catches things `goodTimeStrip` can't.
    private var easyWinsStrip: some View {
        let goodTimeIds = Set(GoodTimeService.shared.ranked(rides: displayedRides, mustDo: appState.wishList).map(\.ride.id))
        let picks = EasyWins.pick(rides: displayedRides, excluding: goodTimeIds)
        return Group {
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").foregroundStyle(.blue)
                        Text("Easy Wins").foregroundStyle(.primary)
                    }
                    .font(.subheadline.weight(.bold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(picks) { ride in
                                Button { selectedRide = ride } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top, spacing: 4) {
                                            if appState.wishList.contains(ride.id) {
                                                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                                            }
                                            Text(ride.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 0)
                                        Text("\(ride.waitMinutes ?? 0) min")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(.blue)
                                    }
                                    .frame(width: 140, alignment: .leading)
                                    .frame(minHeight: 78)
                                    .padding(12)
                                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.blue.opacity(0.4), lineWidth: 1.5))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(ride.name), \(ride.waitMinutes ?? 0) minute wait")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
            }
        }
    }

    private var displayedRides: [DisplayRide] {
        viewModel.filteredRides.filter { ride in
            if showMustDoOnly && !appState.wishList.contains(ride.id) { return false }
            if hideClosed && !ride.isOperating { return false }
            if maxWait > 0 {
                guard ride.isOperating else { return false }
                if let m = ride.waitMinutes, m > maxWait { return false }
            }
            if singleRiderOnly && !RideMetadata.hasSingleRider(name: ride.name, resort: viewModel.selectedGroup) {
                return false
            }
            return true
        }
    }

    private var listFiltersActive: Bool { hideClosed || maxWait > 0 || singleRiderOnly }

    private func parkName(for ride: DisplayRide) -> String {
        viewModel.currentParks.first(where: { $0.id == ride.parkId })?.name ?? ""
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort", selection: $rideSort) {
                ForEach(RideSort.allCases) { Text($0.label).tag($0) }
            }
            Section {
                Toggle("Hide Closed Rides", isOn: $hideClosed)
                Picker("Max Wait", selection: $maxWait) {
                    Text("Any Wait").tag(0)
                    ForEach([15, 30, 45, 60], id: \.self) { Text("≤ \($0) min").tag($0) }
                }
                if viewModel.selectedGroup == .universal || viewModel.selectedGroup == .universalJapan {
                    Toggle("Single Rider Only", isOn: $singleRiderOnly)
                }
            }
            if listFiltersActive {
                Button("Clear Filters", role: .destructive) { clearListFilters() }
            }
        } label: {
            Image(systemName: listFiltersActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .font(.title3)
        }
        .accessibilityLabel("Sort and filter rides")
    }

    private func clearListFilters() {
        hideClosed = false
        maxWait = 0
        singleRiderOnly = false
    }

    /// UIKit version of `rideContextMenu` for long-pressing a map pin.
    private func pinMenu(for ride: DisplayRide) -> UIMenu {
        let isMustDo = appState.wishList.contains(ride.id)
        return UIMenu(title: ride.name, children: [
            UIAction(title: isMustDo ? "Remove from Must-Do" : "Add to Must-Do",
                     image: UIImage(systemName: isMustDo ? "star.slash" : "star")) { _ in
                appState.toggleWish(ride.id)
            },
            UIAction(title: "Add to My Day", image: UIImage(systemName: "calendar.badge.plus")) { _ in
                rideAction = .addToPlan(ride)
            },
            UIAction(title: "Set Wait Alert", image: UIImage(systemName: "bell.badge")) { _ in
                rideAction = .alert(ride)
            },
            UIAction(title: "Details & Rode It", image: UIImage(systemName: "info.circle")) { _ in
                selectedRide = ride
            },
        ])
    }

    @ViewBuilder
    private func rideContextMenu(for ride: DisplayRide) -> some View {
        let isMustDo = appState.wishList.contains(ride.id)
        Button {
            appState.toggleWish(ride.id)
        } label: {
            Label(isMustDo ? "Remove from Must-Do" : "Add to Must-Do",
                  systemImage: isMustDo ? "star.slash" : "star")
        }
        Button {
            rideAction = .addToPlan(ride)
        } label: {
            Label("Add to My Day", systemImage: "calendar.badge.plus")
        }
        Button {
            rideAction = .alert(ride)
        } label: {
            Label("Set Wait Alert", systemImage: "bell.badge")
        }
        Button {
            selectedRide = ride
        } label: {
            Label("Details & Rode It", systemImage: "info.circle")
        }
    }

    private var rideListPanel: some View {
        VStack(spacing: 0) {
            // The whole top of the panel (grabber + park name + crowd/updated line) drags or taps
            // to expand/collapse — not just the little grabber bar
            VStack(spacing: 0) {
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8).padding(.bottom, 6)
                panelHeader
            }
            .contentShape(Rectangle())
            .onTapGesture { panelExpanded.toggle() }
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .updating($panelDrag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        panelExpanded = PanelDrag.shouldExpand(wasExpanded: panelExpanded,
                                                               translation: value.translation.height,
                                                               predicted: value.predictedEndTranslation.height)
                    }
            )
            .accessibilityAction(named: panelExpanded ? "Collapse list" : "Expand list") {
                panelExpanded.toggle()
            }

            // Park Hours Header
            // Only for a specific park — zoomed out to the whole resort there's no single park's hours
            if let park = viewModel.filterPark {
                ParkHoursHeaderView(
                    park: park,
                    schedule: viewModel.todaySchedule(for: park),
                    theme: theme,
                    timeZone: viewModel.selectedGroup.timeZone
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
                ShowsListView(shows: viewModel.currentShows, theme: theme, timeZone: viewModel.selectedGroup.timeZone,
                              resort: viewModel.selectedGroup,
                              parkName: { id in viewModel.currentParks.first { $0.id == id }?.name ?? "" })
            } else if viewModel.isLoadingParks || (viewModel.isLoading && viewModel.allRides.isEmpty) {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg = viewModel.errorMessage, viewModel.allRides.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text(errorMsg).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await viewModel.retry() } }.buttonStyle(.borderedProminent)
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedRides.isEmpty && listFiltersActive && !viewModel.filteredRides.isEmpty {
                ContentUnavailableView {
                    Label("No Rides Match Your Filters", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try a longer max wait or show closed rides.")
                } actions: {
                    Button("Clear Filters") { clearListFilters() }
                        .buttonStyle(.borderedProminent)
                }
            } else if displayedRides.isEmpty {
                ContentUnavailableView(
                    showMustDoOnly ? "No Must-Do Rides" : "No Rides",
                    systemImage: showMustDoOnly ? "star" : "figure.walk",
                    description: Text(showMustDoOnly
                        ? "Star rides in their detail page to add to your Must-Do list."
                        : (viewModel.searchText.isEmpty ? "Loading wait times…" : "No rides match \"\(viewModel.searchText)\"."))
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            NextUpCard(resort: viewModel.selectedGroup)
                            goodTimeStrip
                            easyWinsStrip
                            ForEach(displayedRides) { ride in
                                RideCardView(ride: ride, theme: theme, walkMinutes: walkMinutes(to: ride),
                                             returnPassShort: viewModel.selectedGroup.returnPassNames.short,
                                             returnPassName: viewModel.selectedGroup.returnPassNames.free,
                                             resort: viewModel.selectedGroup,
                                             goodTime: GoodTimeService.shared.deal(for: ride.id),
                                             usual: GoodTimeService.shared.usual(for: ride.id),
                                             trend: viewModel.waitTrends[ride.id],
                                             isMustDo: appState.wishList.contains(ride.id))
                                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .onTapGesture { selectedRide = ride }
                                    .contextMenu { rideContextMenu(for: ride) }
                                    // Same shortcuts as the long-press menu, for VoiceOver's Actions rotor
                                    .accessibilityAction { selectedRide = ride }
                                    .accessibilityAction(named: appState.wishList.contains(ride.id)
                                                         ? "Remove from Must-Do" : "Add to Must-Do") {
                                        appState.toggleWish(ride.id)
                                    }
                                    .accessibilityAction(named: "Add to My Day") { rideAction = .addToPlan(ride) }
                                    .accessibilityAction(named: "Set Wait Alert") { rideAction = .alert(ride) }
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                    }
                    .onChange(of: DeepLinkRouter.shared.waitTimesReselectCount) { _, _ in
                        if let first = displayedRides.first {
                            withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                        }
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: -2)
    }
}

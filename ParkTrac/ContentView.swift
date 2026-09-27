import SwiftUI
import CoreLocation

enum AppTab: Hashable {
    case waitTimes, myDay, bucketList, stats, settings
}

struct ContentView: View {
    @State private var appState = AppState()
    @State private var waitTimesVM = WaitTimesViewModel()
    @State private var selectedTab: AppTab = .waitTimes
    /// Launch screen: pick a resort while wait times start loading underneath
    @State private var showLaunchPicker = LaunchResort.shouldAsk
    @Environment(\.scenePhase) private var scenePhase
    private var router: DeepLinkRouter { .shared }

    /// Tab selection that also reports a tap on the tab that's already selected.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == selectedTab, tab == .waitTimes {
                    router.waitTimesReselectCount += 1
                }
                selectedTab = tab
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if PersistenceController.storageMode == .inMemory {
                StorageWarningBanner()
            }
            ResortBannerView(appState: appState)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            TodayBlockOutBanner(appState: appState)
            ReturnTimeBanner()
            if appState.activeTimerRideId != nil {
                WaitTimerBanner(appState: appState)
            }
            Divider()

            TabView(selection: tabSelection) {
                ParkMapView()
                    .tabItem {
                        Label("Wait Times", systemImage: "clock.fill")
                    }
                    .tag(AppTab.waitTimes)

                DayPlannerView()
                    .tabItem {
                        Label("My Day", systemImage: "list.bullet.clipboard")
                    }
                    .tag(AppTab.myDay)

                BucketListView()
                    .tabItem {
                        Label("Bucket List", systemImage: "checklist")
                    }
                    .tag(AppTab.bucketList)

                StatsView()
                    .tabItem {
                        Label("Stats", systemImage: "chart.bar.fill")
                    }
                    .tag(AppTab.stats)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(AppTab.settings)
            }
            .preferredColorScheme(appState.selectedResort.theme.preferredColorScheme)
            .tint(appState.selectedResort.theme.tabBarTint)
        }
        .overlay(alignment: .bottom) {
            // Sits just above the tab bar
            UndoToast()
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.bottom, 60)
                .animation(.spring(duration: 0.3), value: UndoDeleteCenter.shared.message)
        }
        .overlay {
            if showLaunchPicker && appState.hasCompletedOnboarding {
                LaunchResortView(appState: appState, isLoading: waitTimesVM.isLoadingParks) {
                    withAnimation(.easeOut(duration: 0.3)) { showLaunchPicker = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // Onboarding already asked for the resort — don't show the launch picker right after it
        .onChange(of: appState.hasCompletedOnboarding) { _, done in if done { showLaunchPicker = false } }
        .onOpenURL { url in router.open(url: url) }
        // `initial: true` catches a link that arrived before this view existed (cold launch)
        .onChange(of: router.pending, initial: true) { _, link in
            guard let link else { return }
            handle(link)
            router.pending = nil
        }
        .onChange(of: scenePhase) { _, phase in
            // Don't leave a deletion pending if the app gets suspended or killed
            if phase == .background { UndoDeleteCenter.shared.commit() }
            if phase == .active { appState.reloadTodayGuestsIfNewDay() }
        }
        .environment(appState)
        .environment(waitTimesVM)
        .fullScreenCover(isPresented: Binding(
            get: { !appState.hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
                .environment(appState)
        }
        // Car locator — from the map, My Day, the car pin or thrilltrack://parking
        .sheet(isPresented: Binding(get: { router.showParking }, set: { router.showParking = $0 })) {
            ParkingSheet(resort: appState.selectedResort)
                .environment(appState)
                .environment(waitTimesVM)
        }
        .sheet(isPresented: $appState.showResortPicker) {
            ResortPickerSheet(appState: appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func handle(_ link: DeepLink) {
        // Opened from a notification, Siri, a Home Screen shortcut or a link — go straight there
        showLaunchPicker = false
        switch link {
        case .waitTimes:
            selectedTab = .waitTimes
        case .ride(let id):
            selectedTab = .waitTimes
            router.pendingRideId = id
        case .activeTimer:
            selectedTab = .waitTimes
            router.pendingRideId = appState.activeTimerRideId
        case .plan:
            selectedTab = .myDay
        case .dining:
            selectedTab = .stats
            router.showDining = true
        case .settings:
            selectedTab = .settings
        case .bucketList:
            selectedTab = .bucketList
        case .parking:
            router.showParking = true
        case .planner:
            selectedTab = .myDay
            router.showSmartPlanner = true
        }
    }
}

// MARK: - Storage Warning Banner

private struct StorageWarningBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
            Text("Storage unavailable — changes won't be saved")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red)
    }
}

// MARK: - Resort Banner

private struct ResortBannerView: View {
    let appState: AppState

    var body: some View {
        Button {
            appState.showResortPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: appState.selectedResort.systemImage)
                    .font(.subheadline.weight(.semibold))

                Text(appState.selectedResort.rawValue)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("Switch")
                    .font(.caption.weight(.medium))
                    .opacity(0.75)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(appState.selectedResort.theme.primaryColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Resort Picker Sheet

private struct ResortPickerSheet: View {
    @ScaledMetric(relativeTo: .largeTitle) private var resortIconSize: CGFloat = 36
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Choose Resort")
                .font(.title2.weight(.bold))
                .padding(.top, 8)

            ForEach(["Orlando", "Japan"], id: \.self) { region in
                let resorts = ParkGroup.allCases.filter { $0.isOrlando == (region == "Orlando") }
                VStack(alignment: .leading, spacing: 8) {
                    Text(region)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HStack(spacing: 16) {
                        ForEach(resorts) { resort in
                            resortCard(resort)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    private func resortCard(_ resort: ParkGroup) -> some View {
        let isSelected = appState.selectedResort == resort
        return Button {
            appState.selectedResort = resort
            dismiss()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: resort.systemImage)
                    .font(.system(size: resortIconSize))
                    .foregroundStyle(isSelected ? Color.white : resort.theme.primaryColor)

                Text(resort.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected
                    ? resort.theme.primaryColor
                    : resort.theme.primaryColor.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? resort.theme.primaryColor : resort.theme.primaryColor.opacity(0.2),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Launch resort picker

/// Which resort the launch screen suggests: the one you're at (last known location), else last used.
enum LaunchResort {
    static let askKey = "askResortOnLaunch"
    /// Within this distance of a resort's center counts as "you're here"
    static let nearbyMeters: CLLocationDistance = 10_000

    static var shouldAsk: Bool {
        UserDefaults.standard.object(forKey: askKey) as? Bool ?? true
    }

    static func suggested(last: ParkGroup, location: CLLocationCoordinate2D?) -> ParkGroup {
        guard let location else { return last }
        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let nearest = ParkGroup.allCases
            .map { (resort: $0, distance: here.distance(from: CLLocation(latitude: $0.defaultCoordinate.latitude,
                                                                          longitude: $0.defaultCoordinate.longitude))) }
            .min { $0.distance < $1.distance }
        guard let nearest, nearest.distance <= nearbyMeters else { return last }
        return nearest.resort
    }
}

private struct LaunchResortView: View {
    let appState: AppState
    let isLoading: Bool
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 34
    @State private var suggested: ParkGroup = .disney
    @State private var isNearby = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [suggested.theme.primaryColor.opacity(0.95), suggested.theme.primaryColor.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut, value: suggested)

            VStack(spacing: 22) {
                Spacer(minLength: 12)
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: iconSize, weight: .bold))
                    Text("ThrillTrack")
                        .font(.largeTitle.weight(.heavy))
                    Text("Where are you headed?")
                        .font(.title3.weight(.medium))
                        .opacity(0.9)
                    if let countdown = TripService.shared.countdownText {
                        Label(countdown, systemImage: "airplane")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: Capsule())
                            .padding(.top, 4)
                    }
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

                VStack(spacing: 14) {
                    ForEach(["Orlando", "Japan"], id: \.self) { region in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(region)
                                .font(.caption.weight(.bold))
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.85))
                            HStack(spacing: 12) {
                                ForEach(ParkGroup.allCases.filter { $0.isOrlando == (region == "Orlando") }) { resort in
                                    card(resort)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                HStack(spacing: 8) {
                    if isLoading { ProgressView().tint(.white) }
                    Text(isLoading ? "Loading wait times…" : "Wait times ready")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.bottom, 8)
            }
            .padding(.vertical)
        }
        .onAppear {
            let location = CLLocationManager().location?.coordinate   // last known fix, no prompt
            suggested = LaunchResort.suggested(last: appState.selectedResort, location: location)
            if let location {
                let center = CLLocation(latitude: suggested.defaultCoordinate.latitude,
                                        longitude: suggested.defaultCoordinate.longitude)
                isNearby = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    .distance(from: center) <= LaunchResort.nearbyMeters
            }
        }
    }

    private func card(_ resort: ParkGroup) -> some View {
        let highlighted = resort == suggested
        return Button {
            if appState.selectedResort != resort { appState.selectedResort = resort }
            onDone()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: resort.systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(resort.theme.primaryColor)
                Text(resort.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(highlighted ? (isNearby ? "You're here" : "Last time") : " ")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(resort.theme.primaryColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 6)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(highlighted ? Color.white : Color.clear, lineWidth: 3))
            .shadow(color: .black.opacity(highlighted ? 0.25 : 0.12), radius: highlighted ? 8 : 4, y: 2)
            .scaleEffect(highlighted ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(resort.rawValue + (highlighted ? (isNearby ? ", you're here" : ", last time") : ""))
    }
}

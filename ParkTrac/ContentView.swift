import SwiftUI

enum AppTab: Hashable {
    case waitTimes, myDay, bucketList, stats, settings
}

struct ContentView: View {
    @State private var appState = AppState()
    @State private var waitTimesVM = WaitTimesViewModel()
    @State private var selectedTab: AppTab = .waitTimes
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
        .sheet(isPresented: $appState.showResortPicker) {
            ResortPickerSheet(appState: appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func handle(_ link: DeepLink) {
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

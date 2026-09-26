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
                .presentationDetents([.medium])
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
                .font(.system(size: 13, weight: .semibold))
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
                Image(systemName: appState.selectedResort == .disney
                    ? "crown.fill" : "globe.americas.fill")
                    .font(.system(size: 14, weight: .semibold))

                Text(appState.selectedResort.rawValue)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("Switch")
                    .font(.caption.weight(.medium))
                    .opacity(0.75)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
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
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Choose Resort")
                .font(.title2.weight(.bold))
                .padding(.top, 8)

            HStack(spacing: 16) {
                ForEach(ParkGroup.allCases) { resort in
                    resortCard(resort)
                }
            }
            .padding(.horizontal)

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
                Image(systemName: resort == .disney ? "crown.fill" : "globe.americas.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(isSelected ? Color.white : resort.theme.primaryColor)

                Text(resort.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
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

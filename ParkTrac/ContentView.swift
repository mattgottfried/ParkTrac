import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        VStack(spacing: 0) {
            ResortBannerView(appState: appState)

            TabView {
                ParkMapView()
                    .tabItem {
                        Label("Wait Times", systemImage: "clock.fill")
                    }

                MyDiningView()
                    .tabItem {
                        Label("My Dining", systemImage: "fork.knife")
                    }

                BucketListView()
                    .tabItem {
                        Label("Bucket List", systemImage: "checklist")
                    }

                StatsView()
                    .tabItem {
                        Label("Stats", systemImage: "chart.bar.fill")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
        }
        .environment(appState)
        .sheet(isPresented: $appState.showResortPicker) {
            ResortPickerSheet(appState: appState)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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
                    ? "castle.fill" : "globe.americas.fill")
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
                Image(systemName: resort == .disney ? "castle.fill" : "globe.americas.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(isSelected ? .white : resort.theme.primaryColor)

                Text(resort.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .white : .primary)

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

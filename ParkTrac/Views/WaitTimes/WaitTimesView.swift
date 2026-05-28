import SwiftUI

struct WaitTimesView: View {
    @State private var viewModel = WaitTimesViewModel()
    @State private var showError = false
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Resort segmented picker
                Picker("Resort", selection: $viewModel.selectedGroup) {
                    ForEach(ParkGroup.allCases) { group in
                        Text(group.rawValue).tag(group)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Park hours strip for the filtered park (or first park)
                if let displayPark = viewModel.filterPark ?? viewModel.currentParks.first {
                    let schedule = viewModel.todaySchedule(for: displayPark)
                    ParkHoursHeaderView(
                        park: displayPark,
                        schedule: schedule,
                        theme: viewModel.selectedGroup.theme
                    )
                }

                // Park filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.currentParks) { park in
                            let isSelected = viewModel.filterPark?.id == park.id
                            let weight: Font.Weight = isSelected ? .semibold : .regular
                            Button(action: { viewModel.filterPark = isSelected ? nil : park }) {
                                Text(park.name).fontWeight(weight)
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelected ? Color.blue : Color.secondary)
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
                    let noRidesMsg = viewModel.searchText.isEmpty
                        ? "No attraction data available."
                        : "No rides match \"\(viewModel.searchText)\"."
                    ContentUnavailableView(
                        "No Rides Found",
                        systemImage: "magnifyingglass",
                        description: Text(noRidesMsg)
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.filteredRides) { entry in
                            RideRowView(entry: entry)
                        }

                        // Shows & Entertainment section
                        if !viewModel.currentShows.isEmpty && viewModel.searchText.isEmpty {
                            Section("Shows & Entertainment") {
                                ForEach(viewModel.currentShows) { show in
                                    ShowRowView(show: show, theme: viewModel.selectedGroup.theme)
                                }
                            }
                        }
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
            .onChange(of: appState.sortRidesAlphabetically) { _, newValue in
                viewModel.sortAlphabetical = newValue
            }
        }
        .task {
            viewModel.sortAlphabetical = appState.sortRidesAlphabetically
            await viewModel.loadAllParks()
            viewModel.startAutoRefresh()
        }
        .onDisappear { viewModel.stopAutoRefresh() }
    }
}

// MARK: - Show Row

private struct ShowRowView: View {
    let show: DisplayShow
    let theme: ParkTheme

    @State private var showDetail = false

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 12) {
                // Status dot
                Circle()
                    .fill(show.isOperating ? Color.purple : Color.gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(show.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let next = show.nextShowtime {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("Next: \(Self.timeFmt.string(from: next))")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text(show.isOperating ? "No upcoming times" : show.statusDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "theatermasks.fill")
                    .font(.caption)
                    .foregroundStyle(.purple.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            ShowDetailSheet(show: show, theme: theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Show Detail Sheet

struct ShowDetailSheet: View {
    let show: DisplayShow
    let theme: ParkTheme

    @Environment(\.dismiss) private var dismiss

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let durationFmt: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f
    }()

    private var upcomingShowtimes: [Showtime] {
        let now = Date()
        return show.showtimes.filter { ($0.startDate ?? .distantPast) > now }
    }

    private var pastShowtimes: [Showtime] {
        let now = Date()
        return show.showtimes.filter { ($0.startDate ?? .distantFuture) <= now }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Capsule()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)

                // Title
                VStack(spacing: 8) {
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.purple)

                    Text(show.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Label(show.statusDisplay, systemImage: show.isOperating ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(show.isOperating ? Color.green : Color.secondary)
                }

                Divider()

                // Upcoming showtimes
                VStack(alignment: .leading, spacing: 12) {
                    Label("Today's Schedule", systemImage: "calendar.clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if upcomingShowtimes.isEmpty && pastShowtimes.isEmpty {
                        Text("No show times available")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        // Upcoming
                        ForEach(Array(upcomingShowtimes.enumerated()), id: \.offset) { _, showtime in
                            showtimeRow(showtime, isPast: false)
                        }

                        // Past (dimmed)
                        if !pastShowtimes.isEmpty {
                            Text("Earlier today")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)

                            ForEach(Array(pastShowtimes.enumerated()), id: \.offset) { _, showtime in
                                showtimeRow(showtime, isPast: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentColor)
                    .padding(.top, 4)
            }
            .padding()
        }
    }

    private func showtimeRow(_ showtime: Showtime, isPast: Bool) -> some View {
        HStack {
            Image(systemName: isPast ? "clock.badge.checkmark" : "play.circle.fill")
                .font(.body)
                .foregroundStyle(isPast ? Color.secondary : Color.purple)

            if let start = showtime.startDate {
                let timeWeight: Font.Weight = isPast ? .regular : .semibold
                Text(Self.timeFmt.string(from: start))
                    .font(.subheadline.weight(timeWeight))
                    .foregroundStyle(isPast ? Color.secondary : Color.primary)

                if let end = showtime.endDate {
                    let dur = end.timeIntervalSince(start)
                    if dur > 0, let durStr = Self.durationFmt.string(from: dur) {
                        Text("· \(durStr)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isPast, let start = showtime.startDate {
                    Spacer()
                    let mins = Int(start.timeIntervalSinceNow / 60)
                    if mins < 60 {
                        Text("in \(mins) min")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.purple.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
    }
}

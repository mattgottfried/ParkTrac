import SwiftUI
import SwiftData

struct HotelListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \HotelStay.hotelName) private var allHotels: [HotelStay]
    @State private var selectedHotel: HotelStay?
    @State private var visitedFilter: BucketVisitedFilter = .all
    @State private var tierFilter: String?
    @State private var sortOrder: BucketSortOrder = .name
    @State private var showAddSheet = false

    static func tiers(for resort: ParkGroup) -> [String] {
        resort == .disney
            ? ["Value", "Moderate", "Deluxe", "Disney Vacation Club"]
            : ["Premier", "Preferred", "Standard"]
    }

    private var resortHotels: [HotelStay] {
        allHotels.filter { $0.resort == appState.selectedResort.rawValue }
    }

    private var filtered: [HotelStay] {
        resortHotels
            .filter {
                switch visitedFilter {
                case .all: return true
                case .visited: return $0.isVisited
                case .notVisited: return !$0.isVisited
                }
            }
            .filter { tierFilter == nil || $0.tier == tierFilter }
            .sorted { lhs, rhs in
                switch sortOrder {
                case .name:
                    return lhs.hotelName.localizedCompare(rhs.hotelName) == .orderedAscending
                case .rating:
                    return (lhs.averageRating ?? -1) > (rhs.averageRating ?? -1)
                case .dateVisited:
                    return (lhs.checkIn ?? .distantPast) > (rhs.checkIn ?? .distantPast)
                }
            }
    }

    private var hasActiveFilters: Bool {
        visitedFilter != .all || tierFilter != nil || sortOrder != .name
    }

    var body: some View {
        VStack(spacing: 0) {
            BucketProgressView(
                visited: resortHotels.filter(\.isVisited).count,
                total: resortHotels.count,
                label: "Hotels Stayed",
                color: .purple
            )
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            hotelStatsStrip
                .padding(.bottom, 8)

            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No hotels match the current filters.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { hotel in
                        HotelRow(hotel: hotel)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedHotel = hotel }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $visitedFilter) {
                        ForEach(BucketVisitedFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Tier", selection: $tierFilter) {
                        Text("All Tiers").tag(String?.none)
                        ForEach(Self.tiers(for: appState.selectedResort), id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(BucketSortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: appState.selectedResort) { _, _ in tierFilter = nil }
        .sheet(item: $selectedHotel) { HotelDetailView(hotel: $0) }
        .sheet(isPresented: $showAddSheet) {
            AddHotelSheet(resort: appState.selectedResort)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Stats strip

    private var hotelStatsStrip: some View {
        let resort = appState.selectedResort.rawValue
        let isDisney = appState.selectedResort == .disney
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if isDisney {
                    hotelStatCard(label: "Deluxe / DVC",
                        visited: allHotels.filter { $0.resort == resort && ($0.tier == "Deluxe" || $0.tier == "Disney Vacation Club") && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && ($0.tier == "Deluxe" || $0.tier == "Disney Vacation Club") }.count,
                        color: .purple)
                    hotelStatCard(label: "Moderate",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Moderate" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Moderate" }.count,
                        color: .orange)
                    hotelStatCard(label: "Value",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Value" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Value" }.count,
                        color: .green)
                } else {
                    hotelStatCard(label: "Premier",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Premier" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Premier" }.count,
                        color: .purple)
                    hotelStatCard(label: "Preferred",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Preferred" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Preferred" }.count,
                        color: .orange)
                    hotelStatCard(label: "Standard",
                        visited: allHotels.filter { $0.resort == resort && $0.tier == "Standard" && $0.isVisited }.count,
                        total: allHotels.filter { $0.resort == resort && $0.tier == "Standard" }.count,
                        color: .green)
                }
            }
            .padding(.horizontal)
        }
    }

    private func hotelStatCard(label: String, visited: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? Int((Double(visited) / Double(total) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(visited) / \(total)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text("\(pct)%")
                .font(.caption2)
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HotelRow: View {
    let hotel: HotelStay

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hotel.isVisited ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(hotel.isVisited ? Color.purple : Color.secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(hotel.hotelName)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(hotel.isVisited, color: .secondary)
                HStack(spacing: 6) {
                    Text(hotel.resort)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(hotel.tier)
                        .font(.caption)
                        .foregroundStyle(tierColor(hotel.tier))
                }
                if hotel.isVisited, let checkIn = hotel.checkIn, let nights = hotel.nightsStayed {
                    Text("\(checkIn, style: .date) · \(nights) night\(nights == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if hotel.isVisited, let avg = hotel.averageRating {
                StarDisplayView(rating: avg)
            }
        }
        .padding(.vertical, 4)
    }

    private func tierColor(_ tier: String) -> Color {
        switch tier {
        case "Deluxe", "Premier":    return .purple
        case "Disney Vacation Club": return .blue
        case "Preferred":            return .green
        case "Moderate", "Standard": return .orange
        default:                     return .gray
        }
    }
}

// MARK: - Add Custom Hotel

private struct AddHotelSheet: View {
    let resort: ParkGroup

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var tier: String

    init(resort: ParkGroup) {
        self.resort = resort
        _tier = State(initialValue: HotelListView.tiers(for: resort).first ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hotel") {
                    TextField("Name", text: $name)
                }
                Section {
                    Picker("Tier", selection: $tier) {
                        ForEach(HotelListView.tiers(for: resort), id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Tier")
                } footer: {
                    Text("Added to your \(resort.rawValue) bucket list.")
                }
            }
            .navigationTitle("Add Hotel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let hotel = HotelStay(
            hotelName: name.trimmingCharacters(in: .whitespaces),
            resort: resort.rawValue,
            tier: tier
        )
        context.insert(hotel)
        try? context.save()
        dismiss()
    }
}

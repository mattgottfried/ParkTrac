import SwiftUI
import SwiftData

struct BucketRestaurantListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \BucketRestaurant.name) private var allRestaurants: [BucketRestaurant]
    @State private var searchText: String = ""
    @State private var selectedRestaurant: BucketRestaurant?
    @State private var visitedFilter: BucketVisitedFilter = .all
    @State private var categoryFilter: String?
    @State private var sortOrder: BucketSortOrder = .name
    @State private var showAddSheet = false

    static let categories = ["Quick Service", "Table Service", "Character Dining", "Signature Dining", "Dinner Show"]

    private var resortRestaurants: [BucketRestaurant] {
        allRestaurants.filter { $0.resort == appState.selectedResort.rawValue }
    }

    private var filtered: [BucketRestaurant] {
        resortRestaurants
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .filter {
                switch visitedFilter {
                case .all: return true
                case .visited: return $0.isVisited
                case .notVisited: return !$0.isVisited
                }
            }
            .filter { categoryFilter == nil || $0.category == categoryFilter }
            .sorted { lhs, rhs in
                switch sortOrder {
                case .name:
                    return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                case .rating:
                    return (lhs.averageRating ?? -1) > (rhs.averageRating ?? -1)
                case .dateVisited:
                    return (lhs.visitDate ?? .distantPast) > (rhs.visitDate ?? .distantPast)
                }
            }
    }

    private var hasActiveFilters: Bool {
        visitedFilter != .all || categoryFilter != nil || sortOrder != .name
    }

    var body: some View {
        VStack(spacing: 0) {
            BucketProgressView(
                visited: resortRestaurants.filter(\.isVisited).count,
                total: resortRestaurants.count,
                label: "Restaurants Visited",
                color: .orange
            )
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            statsStrip
                .padding(.bottom, 8)

            Group {
                if !searchText.isEmpty && filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No restaurants match the current filters.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered) { restaurant in
                            BucketRestaurantRow(restaurant: restaurant)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedRestaurant = restaurant }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search restaurants")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $visitedFilter) {
                        ForEach(BucketVisitedFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Category", selection: $categoryFilter) {
                        Text("All Categories").tag(String?.none)
                        ForEach(Self.categories, id: \.self) { Text($0).tag(String?.some($0)) }
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
        .sheet(item: $selectedRestaurant) { BucketRestaurantDetailView(restaurant: $0) }
        .sheet(isPresented: $showAddSheet) {
            AddBucketRestaurantSheet(resort: appState.selectedResort.rawValue)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        let resort = appState.selectedResort.rawValue
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statCard(
                    label: "Table Service",
                    visited: allRestaurants.filter { $0.resort == resort && $0.category == "Table Service" && $0.isVisited }.count,
                    total: allRestaurants.filter { $0.resort == resort && $0.category == "Table Service" }.count,
                    color: .green
                )
                statCard(
                    label: "Quick Service",
                    visited: allRestaurants.filter { $0.resort == resort && $0.category == "Quick Service" && $0.isVisited }.count,
                    total: allRestaurants.filter { $0.resort == resort && $0.category == "Quick Service" }.count,
                    color: .orange
                )
                statCard(
                    label: "Character Dining",
                    visited: allRestaurants.filter { $0.resort == resort && $0.category == "Character Dining" && $0.isVisited }.count,
                    total: allRestaurants.filter { $0.resort == resort && $0.category == "Character Dining" }.count,
                    color: .blue
                )
            }
            .padding(.horizontal)
        }
    }

    private func statCard(label: String, visited: Int, total: Int, color: Color) -> some View {
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

private struct BucketRestaurantRow: View {
    let restaurant: BucketRestaurant

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: restaurant.isVisited ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(restaurant.isVisited ? Color.green : Color.secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(restaurant.isVisited, color: .secondary)
                HStack(spacing: 6) {
                    Text(restaurant.park)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(restaurant.category)
                        .font(.caption)
                        .foregroundStyle(categoryColor(restaurant.category))
                }
                if restaurant.isVisited, let date = restaurant.visitDate {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if restaurant.isVisited, let avg = restaurant.averageRating {
                StarDisplayView(rating: avg)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Character Dining": return .blue
        case "Table Service":    return .green
        default:                 return .gray
        }
    }
}

// MARK: - Add Custom Restaurant

private struct AddBucketRestaurantSheet: View {
    let resort: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var park = ""
    @State private var category = "Table Service"

    var body: some View {
        NavigationStack {
            Form {
                Section("Restaurant") {
                    TextField("Name", text: $name)
                    TextField("Park or location", text: $park)
                }
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(BucketRestaurantListView.categories, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Category")
                } footer: {
                    Text("Added to your \(resort) bucket list.")
                }
            }
            .navigationTitle("Add Restaurant")
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
        let restaurant = BucketRestaurant(
            name: name.trimmingCharacters(in: .whitespaces),
            park: park.trimmingCharacters(in: .whitespaces),
            resort: resort,
            category: category
        )
        context.insert(restaurant)
        try? context.save()
        dismiss()
    }
}

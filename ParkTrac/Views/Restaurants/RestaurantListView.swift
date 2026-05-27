import SwiftUI
import SwiftData

struct RestaurantListView: View {
    @Query(sort: \Restaurant.dateVisited, order: .reverse)
    private var restaurants: [Restaurant]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAdd = false
    @State private var editTarget: Restaurant?
    @State private var pendingDelete: IndexSet?

    var body: some View {
        NavigationStack {
            Group {
                if restaurants.isEmpty {
                    ContentUnavailableView(
                        "No Restaurants Yet",
                        systemImage: "fork.knife",
                        description: Text("Tap + to log a restaurant you've visited.")
                    )
                } else {
                    List {
                        ForEach(restaurants) { restaurant in
                            RestaurantRowView(restaurant: restaurant)
                                .contentShape(Rectangle())
                                .onTapGesture { editTarget = restaurant }
                        }
                        .onDelete { pendingDelete = $0 }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Restaurants")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        Button(action: { showingAdd = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddRestaurantView()
            }
            .sheet(item: $editTarget) { restaurant in
                EditRestaurantView(restaurant: restaurant)
            }
            .confirmationDialog(
                "Delete this restaurant?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let offsets = pendingDelete {
                        offsets.forEach { modelContext.delete(restaurants[$0]) }
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
        }
    }
}

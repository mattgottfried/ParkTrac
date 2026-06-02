import SwiftUI

enum BucketTab: String, CaseIterable {
    case restaurants = "Restaurants"
    case hotels = "Hotels"
}

struct BucketListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: BucketTab = .restaurants

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Category", selection: $selectedTab) {
                    ForEach(BucketTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .restaurants:
                    BucketRestaurantListView()
                case .hotels:
                    HotelListView()
                }
            }
            .navigationTitle("Bucket List")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

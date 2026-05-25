import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            WaitTimesView()
                .tabItem {
                    Label("Wait Times", systemImage: "clock.fill")
                }

            RestaurantListView()
                .tabItem {
                    Label("Restaurants", systemImage: "fork.knife")
                }
        }
    }
}

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ParkMapView()
                .tabItem {
                    Label("Wait Times", systemImage: "clock.fill")
                }

            RestaurantListView()
                .tabItem {
                    Label("My Dining", systemImage: "fork.knife")
                }

            BucketListView()
                .tabItem {
                    Label("Bucket List", systemImage: "checklist")
                }
        }
    }
}

import SwiftUI
import SwiftData

@main
struct ParkTracApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Restaurant.self)
    }
}

import SwiftUI
import SwiftData

@main
struct ParkTracApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            Restaurant.self,
            BucketRestaurant.self,
            HotelStay.self,
            WaitTimeRecord.self,
            DowntimeRecord.self,
        ])
        return try! ModelContainer(for: schema)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await BucketListService.shared.seedIfNeeded(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}

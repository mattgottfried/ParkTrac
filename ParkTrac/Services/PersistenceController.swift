import Foundation
import SwiftData

/// How the app's data store ended up configured at launch.
enum StorageMode {
    /// User data syncs via CloudKit (normal case)
    case cloud
    /// User data persists on device only — CloudKit container unavailable
    case localOnly
    /// Last resort: nothing persists beyond this session
    case inMemory
}

/// Builds the app-wide ModelContainer.
///
/// User data lives in the default store (CloudKit-synced when available).
/// Wait-time telemetry (`WaitTimeRecord` / `DowntimeRecord`) lives in a separate
/// local-only "Telemetry" store so hourly snapshots never round-trip iCloud.
///
/// The user configuration must stay UNNAMED: an unnamed configuration keeps the
/// existing `default.store` URL, so data from installs that predate the split
/// remains readable. Naming it would silently point at a new store file.
enum PersistenceController {

    static let userModels: [any PersistentModel.Type] = [
        BucketRestaurant.self,
        HotelStay.self,
        RideLog.self,
        DiningReservation.self,
        RideAlert.self,
        PlanItem.self,
        PurchaseLog.self,
        Guest.self,
        WaitTimerLog.self,
        VisitSaving.self,
    ]

    static let telemetryModels: [any PersistentModel.Type] = [
        WaitTimeRecord.self,
        DowntimeRecord.self,
    ]

    private(set) static var storageMode: StorageMode = .cloud

    static let container: ModelContainer = {
        let userSchema = Schema(userModels)
        let telemetrySchema = Schema(telemetryModels)
        let fullSchema = Schema(userModels + telemetryModels)

        do {
            let userConfig = ModelConfiguration(schema: userSchema, cloudKitDatabase: .automatic)
            let telemetryConfig = ModelConfiguration("Telemetry", schema: telemetrySchema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: fullSchema, configurations: [userConfig, telemetryConfig])
            storageMode = .cloud
            return container
        } catch {
            print("PersistenceController: CloudKit container failed (\(error)); retrying without sync")
        }

        do {
            let userConfig = ModelConfiguration(schema: userSchema, cloudKitDatabase: .none)
            let telemetryConfig = ModelConfiguration("Telemetry", schema: telemetrySchema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: fullSchema, configurations: [userConfig, telemetryConfig])
            storageMode = .localOnly
            return container
        } catch {
            print("PersistenceController: local container failed (\(error)); falling back to in-memory")
        }

        do {
            let userConfig = ModelConfiguration(schema: userSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let telemetryConfig = ModelConfiguration("Telemetry", schema: telemetrySchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: fullSchema, configurations: [userConfig, telemetryConfig])
            storageMode = .inMemory
            return container
        } catch {
            fatalError("PersistenceController: even in-memory container failed: \(error)")
        }
    }()

    /// Telemetry-only container for the background refresh task.
    /// Must use the same named "Telemetry" configuration so background writes
    /// land in the exact store the foreground app reads.
    static func makeTelemetryContainer() throws -> ModelContainer {
        let telemetrySchema = Schema(telemetryModels)
        let config = ModelConfiguration("Telemetry", schema: telemetrySchema, cloudKitDatabase: .none)
        return try ModelContainer(for: telemetrySchema, configurations: [config])
    }
}

import Foundation
import SwiftData
import CloudKit

enum HouseholdSyncError: LocalizedError {
    case invalidCode
    case codeNotFound
    case codeGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "Enter a household code."
        case .codeNotFound: return "That code wasn't found. Double-check it and try again."
        case .codeGenerationFailed: return "Couldn't generate a unique code. Try again."
        }
    }
}

/// Hand-rolled CloudKit sync layer that shares all user data across two Apple IDs via a
/// typed "household code" — separate from and additive to SwiftData's own per-account
/// private-database CloudKit sync (`PersistenceController`).
///
/// Records live in CloudKit's **public database** (default zone — the public database
/// doesn't support custom zones), each tagged with a `householdCode` field. Any device
/// that knows the code can read/write that household's records; there's no invite/accept
/// step, so the code should be treated like a shared PIN, not a password.
///
/// Change detection is a periodic reconciliation scan (fingerprint each local row, diff
/// against a small local index), not `ModelContext.didSave` notification-diffing — that
/// notification is unreliable before iOS 18.1, which is below this app's iOS 17 minimum.
/// See `HouseholdSyncIndex` for the fingerprint/watermark bookkeeping this relies on.
@MainActor
@Observable
final class HouseholdSyncService {
    static let shared = HouseholdSyncService()

    private static let codeKey = "householdCode"
    private static let joinedAtKey = "householdJoinedAt"
    private static let tombstoneRecordType = "Household_Tombstone"
    private static let householdMarkerRecordType = "Household"
    private static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789") // excludes 0/O/1/I/L
    private static let foregroundSyncInterval: TimeInterval = 50

    private static let allRecordTypes: [String] = [
        RideLog.ckRecordType, DiningReservation.ckRecordType, RideAlert.ckRecordType,
        PlanItem.ckRecordType, PurchaseLog.ckRecordType, Guest.ckRecordType,
        WaitTimerLog.ckRecordType, VisitSaving.ckRecordType, BucketRestaurant.ckRecordType,
        HotelStay.ckRecordType, RestaurantRating.ckRecordType, HotelRating.ckRecordType,
        tombstoneRecordType,
    ]

    private(set) var currentCode: String?
    private(set) var joinedAt: Date?
    private(set) var lastSyncedAt: Date?
    private(set) var lastSyncError: String?
    private(set) var isSyncing: Bool = false

    private let container = PersistenceController.container
    private let database = CKContainer.default().publicCloudDatabase
    private var syncTimer: Timer?

    private init() {
        currentCode = UserDefaults.standard.string(forKey: Self.codeKey)
        joinedAt = UserDefaults.standard.object(forKey: Self.joinedAtKey) as? Date
    }

    // MARK: - Lifecycle triggers (called from ParkTracApp / AppDelegate)

    func appDidLaunch() {
        guard currentCode != nil else { return }
        startTimerIfNeeded()
        Task {
            await self.registerSubscriptionsIfNeeded()
            await self.runFullSync()
        }
    }

    func sceneDidBecomeActive() {
        guard currentCode != nil else { return }
        startTimerIfNeeded()
        Task { await runFullSync() }
    }

    func sceneDidEnterBackground() {
        stopTimer()
    }

    @discardableResult
    func handleRemotePush() async -> Bool {
        guard currentCode != nil else { return false }
        await runFullSync()
        return true
    }

    // MARK: - Create / Join / Leave

    func create() async throws -> String {
        for _ in 0..<5 {
            let code = Self.generateCode()
            let recordID = CKRecord.ID(recordName: code)
            do {
                _ = try await database.record(for: recordID)
                continue // record already exists — collision, try another code
            } catch let error as CKError where error.code == .unknownItem {
                let record = CKRecord(recordType: Self.householdMarkerRecordType, recordID: recordID)
                record["createdAt"] = Date()
                _ = try await database.save(record)
                await adopt(code: code)
                return code
            }
        }
        throw HouseholdSyncError.codeGenerationFailed
    }

    func join(code rawCode: String) async throws {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { throw HouseholdSyncError.invalidCode }

        let recordID = CKRecord.ID(recordName: code)
        do {
            _ = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            throw HouseholdSyncError.codeNotFound
        }
        await adopt(code: code)
    }

    func leave() {
        guard let code = currentCode else { return }
        stopTimer()
        Task { await deleteSubscriptions(code: code) }
        UserDefaults.standard.removeObject(forKey: Self.codeKey)
        UserDefaults.standard.removeObject(forKey: Self.joinedAtKey)
        HouseholdSyncIndex.reset()
        currentCode = nil
        joinedAt = nil
        lastSyncedAt = nil
        lastSyncError = nil
    }

    private func adopt(code: String) async {
        currentCode = code
        joinedAt = Date()
        UserDefaults.standard.set(code, forKey: Self.codeKey)
        UserDefaults.standard.set(joinedAt, forKey: Self.joinedAtKey)
        HouseholdSyncIndex.reset()
        startTimerIfNeeded()
        await registerSubscriptionsIfNeeded()
        await runFullSync()
    }

    private static func generateCode(length: Int = 6) -> String {
        String((0..<length).compactMap { _ in codeAlphabet.randomElement() })
    }

    // MARK: - Full sync orchestration

    func runFullSync() async {
        guard let code = currentCode, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var index = HouseholdSyncIndex.load()
        let context = container.mainContext

        await uploadAll(context: context, code: code, index: &index)
        await downloadAll(context: context, code: code, index: &index)

        index.save()
        if context.hasChanges {
            try? context.save()
        }
        lastSyncedAt = Date()
    }

    private func uploadAll(context: ModelContext, code: String, index: inout HouseholdSyncIndex) async {
        await reconcileUpload(RideLog.self, context: context, code: code, index: &index)
        await reconcileUpload(DiningReservation.self, context: context, code: code, index: &index)
        await reconcileUpload(RideAlert.self, context: context, code: code, index: &index)
        await reconcileUpload(PlanItem.self, context: context, code: code, index: &index)
        await reconcileUpload(PurchaseLog.self, context: context, code: code, index: &index)
        await reconcileUpload(Guest.self, context: context, code: code, index: &index)
        await reconcileUpload(WaitTimerLog.self, context: context, code: code, index: &index)
        await reconcileUpload(VisitSaving.self, context: context, code: code, index: &index)
        await reconcileUpload(BucketRestaurant.self, context: context, code: code, index: &index)
        await reconcileUpload(HotelStay.self, context: context, code: code, index: &index)
        await reconcileUpload(RestaurantRating.self, context: context, code: code, index: &index)
        await reconcileUpload(HotelRating.self, context: context, code: code, index: &index)
    }

    private func downloadAll(context: ModelContext, code: String, index: inout HouseholdSyncIndex) async {
        await downloadType(RideLog.self, context: context, code: code, index: &index)
        await downloadType(DiningReservation.self, context: context, code: code, index: &index)
        await downloadType(RideAlert.self, context: context, code: code, index: &index)
        await downloadType(PlanItem.self, context: context, code: code, index: &index)
        await downloadType(PurchaseLog.self, context: context, code: code, index: &index)
        await downloadType(Guest.self, context: context, code: code, index: &index)
        await downloadType(WaitTimerLog.self, context: context, code: code, index: &index)
        await downloadType(VisitSaving.self, context: context, code: code, index: &index)
        await downloadType(BucketRestaurant.self, context: context, code: code, index: &index)
        await downloadType(HotelStay.self, context: context, code: code, index: &index)
        await downloadType(RestaurantRating.self, context: context, code: code, index: &index)
        await downloadType(HotelRating.self, context: context, code: code, index: &index)
        await downloadTombstones(context: context, code: code, index: &index)
    }

    // MARK: - Upload (local changes -> CloudKit)

    /// Fingerprints every local row of `T`, uploads anything changed since the last pass,
    /// and detects local deletes by diffing against the ids known from the last pass —
    /// no `PersistentIdentifier` bookkeeping needed since the index is keyed by the
    /// model's own stable `id: UUID`.
    private func reconcileUpload<T: HouseholdSyncable>(
        _ type: T.Type, context: ModelContext, code: String, index: inout HouseholdSyncIndex
    ) async {
        let typeName = T.ckRecordType
        guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }

        var changedRows: [(row: T, fingerprint: String, record: CKRecord)] = []
        var seenIds = Set<UUID>()

        for row in rows {
            seenIds.insert(row.id)
            let fingerprint = row.householdFingerprint()
            guard index.fingerprint(typeName: typeName, id: row.id) != fingerprint else { continue }

            let stamp = Date()
            let record = CKRecord(recordType: typeName, recordID: CKRecord.ID(recordName: row.id.uuidString))
            record["householdCode"] = code
            record["syncUpdatedAt"] = stamp
            row.populateHouseholdFields(on: record)
            row.syncUpdatedAt = stamp
            changedRows.append((row, fingerprint, record))
        }

        var deletedIds: [UUID] = []
        var toDelete: [CKRecord.ID] = []
        var tombstones: [CKRecord] = []
        for deletedId in index.knownIds(typeName: typeName).subtracting(seenIds) {
            deletedIds.append(deletedId)
            toDelete.append(CKRecord.ID(recordName: deletedId.uuidString))
            let tombstone = CKRecord(recordType: Self.tombstoneRecordType)
            tombstone["householdCode"] = code
            // NB: "recordType" is a reserved CKRecord system field name — using it as a
            // custom key throws an uncaught NSException and crashes. Use a distinct name.
            tombstone["syncedRecordType"] = typeName
            tombstone["deletedId"] = deletedId.uuidString
            tombstone["deletedAt"] = Date()
            tombstones.append(tombstone)
        }

        guard !changedRows.isEmpty || !toDelete.isEmpty else { return }

        let toSave = changedRows.map(\.record) + tombstones
        guard let (saveResults, _) = try? await database.modifyRecords(
            saving: toSave, deleting: toDelete, savePolicy: .changedKeys, atomically: false
        ) else { return } // top-level failure (e.g. offline) — index untouched, retried next pass

        for (row, fingerprint, record) in changedRows {
            switch saveResults[record.recordID] {
            case .success:
                index.setFingerprint(fingerprint, typeName: typeName, id: row.id)
            case .failure(let error):
                await resolveUploadConflict(row: row, error: error, code: code, typeName: typeName, index: &index)
            case .none:
                break
            }
        }

        // Either the delete succeeded or the record was already gone server-side —
        // both cases mean "no fingerprint should remain" locally.
        for id in deletedIds {
            index.removeFingerprint(typeName: typeName, id: id)
        }
    }

    private func resolveUploadConflict<T: HouseholdSyncable>(
        row: T, error: Error, code: String, typeName: String, index: inout HouseholdSyncIndex
    ) async {
        guard let ckError = error as? CKError, ckError.code == .serverRecordChanged,
              let serverRecord = ckError.serverRecord else { return }

        let serverUpdatedAt = serverRecord["syncUpdatedAt"] as? Date ?? .distantPast
        if serverUpdatedAt >= row.syncUpdatedAt {
            // Server wins — adopt its fields locally.
            row.applyHouseholdFields(from: serverRecord)
            row.syncUpdatedAt = serverUpdatedAt
            index.setFingerprint(row.householdFingerprint(), typeName: typeName, id: row.id)
        } else {
            // We win — resubmit using the server's record so we carry the right change tag.
            serverRecord["householdCode"] = code
            serverRecord["syncUpdatedAt"] = row.syncUpdatedAt
            row.populateHouseholdFields(on: serverRecord)
            if (try? await database.save(serverRecord)) != nil {
                index.setFingerprint(row.householdFingerprint(), typeName: typeName, id: row.id)
            }
        }
    }

    // MARK: - Download (CloudKit -> local)

    private func downloadType<T: HouseholdSyncable>(
        _ type: T.Type, context: ModelContext, code: String, index: inout HouseholdSyncIndex
    ) async {
        let typeName = T.ckRecordType
        let watermark = index.downloadWatermark(typeName: typeName)
        let predicate = NSPredicate(format: "householdCode == %@ AND syncUpdatedAt > %@", code, watermark as NSDate)
        let query = CKQuery(recordType: typeName, predicate: predicate)

        guard let (results, _) = try? await database.records(matching: query), !results.isEmpty else { return }

        var maxSeen = watermark
        let existing = (try? context.fetch(FetchDescriptor<T>())) ?? []
        var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for (recordID, result) in results {
            guard case .success(let record) = result,
                  let uuid = UUID(uuidString: recordID.recordName) else { continue }
            let remoteUpdatedAt = record["syncUpdatedAt"] as? Date ?? Date()
            maxSeen = max(maxSeen, remoteUpdatedAt)

            if let localRow = byId[uuid] {
                guard remoteUpdatedAt > localRow.syncUpdatedAt else { continue }
                localRow.applyHouseholdFields(from: record)
                localRow.syncUpdatedAt = remoteUpdatedAt
                index.setFingerprint(localRow.householdFingerprint(), typeName: typeName, id: uuid)
            } else {
                let newRow = T.makeHouseholdPlaceholder(id: uuid)
                newRow.applyHouseholdFields(from: record)
                newRow.syncUpdatedAt = remoteUpdatedAt
                context.insert(newRow)
                byId[uuid] = newRow
                index.setFingerprint(newRow.householdFingerprint(), typeName: typeName, id: uuid)
            }
        }

        index.advanceDownloadWatermark(maxSeen, typeName: typeName)
    }

    private func downloadTombstones(context: ModelContext, code: String, index: inout HouseholdSyncIndex) async {
        let watermark = index.downloadWatermark(typeName: Self.tombstoneRecordType)
        let predicate = NSPredicate(format: "householdCode == %@ AND deletedAt > %@", code, watermark as NSDate)
        let query = CKQuery(recordType: Self.tombstoneRecordType, predicate: predicate)

        guard let (results, _) = try? await database.records(matching: query), !results.isEmpty else { return }

        var maxSeen = watermark
        for (_, result) in results {
            guard case .success(let record) = result,
                  let recordTypeName = record["syncedRecordType"] as? String,
                  let deletedIdString = record["deletedId"] as? String,
                  let deletedId = UUID(uuidString: deletedIdString),
                  let deletedAt = record["deletedAt"] as? Date else { continue }
            maxSeen = max(maxSeen, deletedAt)
            applyTombstone(ckRecordType: recordTypeName, deletedId: deletedId, context: context)
            index.removeFingerprint(typeName: recordTypeName, id: deletedId)
        }
        index.advanceDownloadWatermark(maxSeen, typeName: Self.tombstoneRecordType)
    }

    private func applyTombstone(ckRecordType: String, deletedId: UUID, context: ModelContext) {
        switch ckRecordType {
        case RideLog.ckRecordType: deleteLocalRow(RideLog.self, id: deletedId, context: context)
        case DiningReservation.ckRecordType: deleteLocalRow(DiningReservation.self, id: deletedId, context: context)
        case RideAlert.ckRecordType: deleteLocalRow(RideAlert.self, id: deletedId, context: context)
        case PlanItem.ckRecordType: deleteLocalRow(PlanItem.self, id: deletedId, context: context)
        case PurchaseLog.ckRecordType: deleteLocalRow(PurchaseLog.self, id: deletedId, context: context)
        case Guest.ckRecordType: deleteLocalRow(Guest.self, id: deletedId, context: context)
        case WaitTimerLog.ckRecordType: deleteLocalRow(WaitTimerLog.self, id: deletedId, context: context)
        case VisitSaving.ckRecordType: deleteLocalRow(VisitSaving.self, id: deletedId, context: context)
        case BucketRestaurant.ckRecordType: deleteLocalRow(BucketRestaurant.self, id: deletedId, context: context)
        case HotelStay.ckRecordType: deleteLocalRow(HotelStay.self, id: deletedId, context: context)
        case RestaurantRating.ckRecordType: deleteLocalRow(RestaurantRating.self, id: deletedId, context: context)
        case HotelRating.ckRecordType: deleteLocalRow(HotelRating.self, id: deletedId, context: context)
        default: break
        }
    }

    // NB: deliberately not using #Predicate here — the macro can't reliably resolve a
    // keypath-to-string mapping for a generic PersistentModel type parameter at runtime;
    // it crashes inside SwiftData's Schema.generateString(for:at:) (confirmed via a real
    // TestFlight crash report). Fetching all rows and filtering with a plain closure is
    // completely safe and fine at this app's scale.
    private func deleteLocalRow<T: HouseholdSyncable>(_ type: T.Type, id: UUID, context: ModelContext) {
        guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }
        if let row = rows.first(where: { $0.id == id }) {
            context.delete(row)
        }
    }

    // MARK: - Subscriptions (silent push)

    private func registerSubscriptionsIfNeeded() async {
        guard let code = currentCode else { return }
        let registeredKey = "householdSubscriptionsRegistered_\(code)"
        guard !UserDefaults.standard.bool(forKey: registeredKey) else { return }

        let subscriptions: [CKSubscription] = Self.allRecordTypes.map { recordType in
            let subscription = CKQuerySubscription(
                recordType: recordType,
                predicate: NSPredicate(format: "householdCode == %@", code),
                subscriptionID: "household-\(code)-\(recordType)",
                options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
            )
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            return subscription
        }

        do {
            _ = try await database.modifySubscriptions(saving: subscriptions, deleting: [])
            UserDefaults.standard.set(true, forKey: registeredKey)
        } catch {
            // Best-effort — the foreground timer and background-task fallback still cover sync.
        }
    }

    private func deleteSubscriptions(code: String) async {
        let ids = Self.allRecordTypes.map { CKSubscription.ID("household-\(code)-\($0)") }
        _ = try? await database.modifySubscriptions(saving: [], deleting: ids)
        UserDefaults.standard.removeObject(forKey: "householdSubscriptionsRegistered_\(code)")
    }

    // MARK: - Foreground timer

    private func startTimerIfNeeded() {
        guard syncTimer == nil else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: Self.foregroundSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runFullSync()
            }
        }
    }

    private func stopTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
}

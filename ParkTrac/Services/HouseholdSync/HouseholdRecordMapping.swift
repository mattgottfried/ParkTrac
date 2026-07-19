import Foundation
import SwiftData
import CloudKit

/// A SwiftData model that participates in household sharing. Conformances live here
/// (not in the model files) so the sync feature stays easy to lift out later.
///
/// `id`/`syncUpdatedAt` are declared on every conforming model already (see Models/*.swift);
/// this protocol just names them so generic sync code can read/write them without knowing
/// the concrete type. `populateHouseholdFields`/`applyHouseholdFields` only ever touch
/// domain fields — `id`, `householdCode`, and `syncUpdatedAt` are handled centrally by
/// `HouseholdSyncService` so every model doesn't have to repeat that bookkeeping.
protocol HouseholdSyncable: PersistentModel {
    static var ckRecordType: String { get }
    var id: UUID { get set }
    var syncUpdatedAt: Date { get set }

    /// Builds a blank row to insert locally for a record downloaded from another device
    /// that has no local counterpart yet. Field values are placeholders — the caller
    /// immediately overwrites them via `applyHouseholdFields(from:)`. Needed because each
    /// model's designated initializer has a different signature, so there's no single
    /// generic way to construct one.
    static func makeHouseholdPlaceholder(id: UUID) -> Self

    func householdFingerprint() -> String
    func populateHouseholdFields(on record: CKRecord)
    func applyHouseholdFields(from record: CKRecord)
}

private func str(_ value: String?) -> String { value ?? "" }
private func num(_ value: Int?) -> String { value.map(String.init) ?? "" }
private func iso(_ value: Date?) -> String { value.map { ISO8601DateFormatter().string(from: $0) } ?? "" }

// MARK: - RideLog

extension RideLog: HouseholdSyncable {
    static var ckRecordType: String { "Household_RideLog" }

    static func makeHouseholdPlaceholder(id: UUID) -> RideLog {
        let row = RideLog(rideId: "", rideName: "", parkId: "", parkName: "", resort: "")
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            rideId, rideName, parkId, parkName, resort,
            iso(riddenAt), num(waitMinutes), num(actualWaitMinutes), notes,
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["rideId"] = rideId
        record["rideName"] = rideName
        record["parkId"] = parkId
        record["parkName"] = parkName
        record["resort"] = resort
        record["riddenAt"] = riddenAt
        record["waitMinutes"] = waitMinutes
        record["actualWaitMinutes"] = actualWaitMinutes
        record["notes"] = notes
    }

    func applyHouseholdFields(from record: CKRecord) {
        rideId = record["rideId"] as? String ?? ""
        rideName = record["rideName"] as? String ?? ""
        parkId = record["parkId"] as? String ?? ""
        parkName = record["parkName"] as? String ?? ""
        resort = record["resort"] as? String ?? ""
        riddenAt = record["riddenAt"] as? Date ?? Date()
        waitMinutes = record["waitMinutes"] as? Int
        actualWaitMinutes = record["actualWaitMinutes"] as? Int
        notes = record["notes"] as? String ?? ""
    }
}

// MARK: - DiningReservation

extension DiningReservation: HouseholdSyncable {
    static var ckRecordType: String { "Household_DiningReservation" }

    static func makeHouseholdPlaceholder(id: UUID) -> DiningReservation {
        let row = DiningReservation(restaurantName: "", resort: "", date: Date())
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            restaurantName, resort, iso(date), String(partySize),
            confirmationNumber, notes, String(isCompleted),
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["restaurantName"] = restaurantName
        record["resort"] = resort
        record["date"] = date
        record["partySize"] = partySize
        record["confirmationNumber"] = confirmationNumber
        record["notes"] = notes
        record["isCompleted"] = isCompleted
    }

    func applyHouseholdFields(from record: CKRecord) {
        restaurantName = record["restaurantName"] as? String ?? ""
        resort = record["resort"] as? String ?? ""
        date = record["date"] as? Date ?? Date()
        partySize = record["partySize"] as? Int ?? 2
        confirmationNumber = record["confirmationNumber"] as? String ?? ""
        notes = record["notes"] as? String ?? ""
        isCompleted = (record["isCompleted"] as? Int ?? 0) != 0
    }
}

// MARK: - RideAlert

extension RideAlert: HouseholdSyncable {
    static var ckRecordType: String { "Household_RideAlert" }

    static func makeHouseholdPlaceholder(id: UUID) -> RideAlert {
        let row = RideAlert(rideId: "", rideName: "", thresholdMinutes: 0)
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            rideId, rideName, String(thresholdMinutes), String(isActive), iso(createdAt),
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["rideId"] = rideId
        record["rideName"] = rideName
        record["thresholdMinutes"] = thresholdMinutes
        record["isActive"] = isActive
        record["createdAt"] = createdAt
    }

    func applyHouseholdFields(from record: CKRecord) {
        rideId = record["rideId"] as? String ?? ""
        rideName = record["rideName"] as? String ?? ""
        thresholdMinutes = record["thresholdMinutes"] as? Int ?? 0
        isActive = (record["isActive"] as? Int ?? 1) != 0
        createdAt = record["createdAt"] as? Date ?? Date()
    }
}

// MARK: - PlanItem

extension PlanItem: HouseholdSyncable {
    static var ckRecordType: String { "Household_PlanItem" }

    static func makeHouseholdPlaceholder(id: UUID) -> PlanItem {
        let row = PlanItem(title: "")
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            iso(date), iso(scheduledTime), title, kind, str(rideId), parkName, resort,
            notes, String(isDone), String(sortOrder), iso(llReturnStart), iso(llReturnEnd),
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["date"] = date
        record["scheduledTime"] = scheduledTime
        record["title"] = title
        record["kind"] = kind
        record["rideId"] = rideId
        record["parkName"] = parkName
        record["resort"] = resort
        record["notes"] = notes
        record["isDone"] = isDone
        record["sortOrder"] = sortOrder
        record["llReturnStart"] = llReturnStart
        record["llReturnEnd"] = llReturnEnd
    }

    func applyHouseholdFields(from record: CKRecord) {
        date = record["date"] as? Date ?? Date()
        scheduledTime = record["scheduledTime"] as? Date
        title = record["title"] as? String ?? ""
        kind = record["kind"] as? String ?? "note"
        rideId = record["rideId"] as? String
        parkName = record["parkName"] as? String ?? ""
        resort = record["resort"] as? String ?? ""
        notes = record["notes"] as? String ?? ""
        isDone = (record["isDone"] as? Int ?? 0) != 0
        sortOrder = record["sortOrder"] as? Int ?? 0
        llReturnStart = record["llReturnStart"] as? Date
        llReturnEnd = record["llReturnEnd"] as? Date
    }
}

// MARK: - PurchaseLog

extension PurchaseLog: HouseholdSyncable {
    static var ckRecordType: String { "Household_PurchaseLog" }

    static func makeHouseholdPlaceholder(id: UUID) -> PurchaseLog {
        let row = PurchaseLog(amount: 0, category: "", resort: "")
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            String(amount), category, iso(date), resort, note, String(isAPEligible),
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["amount"] = amount
        record["category"] = category
        record["date"] = date
        record["resort"] = resort
        record["note"] = note
        record["isAPEligible"] = isAPEligible
    }

    func applyHouseholdFields(from record: CKRecord) {
        amount = record["amount"] as? Double ?? 0
        category = record["category"] as? String ?? ""
        date = record["date"] as? Date ?? Date()
        resort = record["resort"] as? String ?? ""
        note = record["note"] as? String ?? ""
        isAPEligible = (record["isAPEligible"] as? Int ?? 1) != 0
    }
}

// MARK: - Guest

extension Guest: HouseholdSyncable {
    static var ckRecordType: String { "Household_Guest" }

    static func makeHouseholdPlaceholder(id: UUID) -> Guest {
        let row = Guest(name: "")
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            name, String(hasDisneyPass), String(hasUniversalPass),
            disneyPassTier, universalPassTier, String(isFrequent),
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["name"] = name
        record["hasDisneyPass"] = hasDisneyPass
        record["hasUniversalPass"] = hasUniversalPass
        record["disneyPassTier"] = disneyPassTier
        record["universalPassTier"] = universalPassTier
        record["isFrequent"] = isFrequent
    }

    func applyHouseholdFields(from record: CKRecord) {
        name = record["name"] as? String ?? ""
        hasDisneyPass = (record["hasDisneyPass"] as? Int ?? 0) != 0
        hasUniversalPass = (record["hasUniversalPass"] as? Int ?? 0) != 0
        disneyPassTier = record["disneyPassTier"] as? String ?? ""
        universalPassTier = record["universalPassTier"] as? String ?? ""
        isFrequent = (record["isFrequent"] as? Int ?? 1) != 0
    }
}

// MARK: - WaitTimerLog

extension WaitTimerLog: HouseholdSyncable {
    static var ckRecordType: String { "Household_WaitTimerLog" }

    static func makeHouseholdPlaceholder(id: UUID) -> WaitTimerLog {
        let row = WaitTimerLog(rideId: "", rideName: "", resort: "", postedMinutes: 0, actualMinutes: 0, startedAt: Date())
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            rideId, rideName, resort, String(postedMinutes), String(actualMinutes), iso(startedAt),
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["rideId"] = rideId
        record["rideName"] = rideName
        record["resort"] = resort
        record["postedMinutes"] = postedMinutes
        record["actualMinutes"] = actualMinutes
        record["startedAt"] = startedAt
    }

    func applyHouseholdFields(from record: CKRecord) {
        rideId = record["rideId"] as? String ?? ""
        rideName = record["rideName"] as? String ?? ""
        resort = record["resort"] as? String ?? ""
        postedMinutes = record["postedMinutes"] as? Int ?? 0
        actualMinutes = record["actualMinutes"] as? Int ?? 0
        startedAt = record["startedAt"] as? Date ?? Date()
    }
}

// MARK: - VisitSaving

extension VisitSaving: HouseholdSyncable {
    static var ckRecordType: String { "Household_VisitSaving" }

    static func makeHouseholdPlaceholder(id: UUID) -> VisitSaving {
        let row = VisitSaving(resort: "", gateValue: 0)
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            iso(date), resort, String(gateValue), note, String(parkingValue), parkingType,
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["date"] = date
        record["resort"] = resort
        record["gateValue"] = gateValue
        record["note"] = note
        record["parkingValue"] = parkingValue
        record["parkingType"] = parkingType
    }

    func applyHouseholdFields(from record: CKRecord) {
        date = record["date"] as? Date ?? Date()
        resort = record["resort"] as? String ?? ""
        gateValue = record["gateValue"] as? Double ?? 0
        note = record["note"] as? String ?? ""
        parkingValue = record["parkingValue"] as? Double ?? 0
        parkingType = record["parkingType"] as? String ?? ""
    }
}

// MARK: - BucketRestaurant
// Note: photoData (@Attribute(.externalStorage)) is intentionally excluded from v1 sync.

extension BucketRestaurant: HouseholdSyncable {
    static var ckRecordType: String { "Household_BucketRestaurant" }

    static func makeHouseholdPlaceholder(id: UUID) -> BucketRestaurant {
        let row = BucketRestaurant(name: "", park: "", resort: "", category: "")
        row.id = id
        return row
    }

    // mattRating/wifeRating are intentionally excluded — ratings now live in
    // RestaurantRating rows, synced independently (see below).
    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            name, park, resort, category, String(isVisited), iso(visitDate), notes, String(isFromAPI),
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["name"] = name
        record["park"] = park
        record["resort"] = resort
        record["category"] = category
        record["isVisited"] = isVisited
        record["visitDate"] = visitDate
        record["notes"] = notes
        record["isFromAPI"] = isFromAPI
    }

    func applyHouseholdFields(from record: CKRecord) {
        name = record["name"] as? String ?? ""
        park = record["park"] as? String ?? ""
        resort = record["resort"] as? String ?? ""
        category = record["category"] as? String ?? ""
        isVisited = (record["isVisited"] as? Int ?? 0) != 0
        visitDate = record["visitDate"] as? Date
        notes = record["notes"] as? String ?? ""
        isFromAPI = (record["isFromAPI"] as? Int ?? 0) != 0
    }
}

// MARK: - HotelStay
// Note: photoData (@Attribute(.externalStorage)) is intentionally excluded from v1 sync.

extension HotelStay: HouseholdSyncable {
    static var ckRecordType: String { "Household_HotelStay" }

    static func makeHouseholdPlaceholder(id: UUID) -> HotelStay {
        let row = HotelStay(hotelName: "", resort: "", tier: "")
        row.id = id
        return row
    }

    // mattRating/wifeRating are intentionally excluded — ratings now live in
    // HotelRating rows, synced independently (see below).
    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([
            hotelName, resort, tier, String(isVisited), iso(checkIn), iso(checkOut), roomType, notes,
        ])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["hotelName"] = hotelName
        record["resort"] = resort
        record["tier"] = tier
        record["isVisited"] = isVisited
        record["checkIn"] = checkIn
        record["checkOut"] = checkOut
        record["roomType"] = roomType
        record["notes"] = notes
    }

    func applyHouseholdFields(from record: CKRecord) {
        hotelName = record["hotelName"] as? String ?? ""
        resort = record["resort"] as? String ?? ""
        tier = record["tier"] as? String ?? ""
        isVisited = (record["isVisited"] as? Int ?? 0) != 0
        checkIn = record["checkIn"] as? Date
        checkOut = record["checkOut"] as? Date
        roomType = record["roomType"] as? String ?? ""
        notes = record["notes"] as? String ?? ""
    }
}

// MARK: - RestaurantRating

extension RestaurantRating: HouseholdSyncable {
    static var ckRecordType: String { "Household_RestaurantRating" }

    static func makeHouseholdPlaceholder(id: UUID) -> RestaurantRating {
        let row = RestaurantRating(restaurantId: UUID(), guestId: UUID(), stars: 0)
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([restaurantId.uuidString, guestId.uuidString, String(stars)])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["restaurantId"] = restaurantId.uuidString
        record["guestId"] = guestId.uuidString
        record["stars"] = stars
    }

    func applyHouseholdFields(from record: CKRecord) {
        restaurantId = UUID(uuidString: record["restaurantId"] as? String ?? "") ?? UUID()
        guestId = UUID(uuidString: record["guestId"] as? String ?? "") ?? UUID()
        stars = record["stars"] as? Int ?? 0
    }
}

// MARK: - HotelRating

extension HotelRating: HouseholdSyncable {
    static var ckRecordType: String { "Household_HotelRating" }

    static func makeHouseholdPlaceholder(id: UUID) -> HotelRating {
        let row = HotelRating(hotelId: UUID(), guestId: UUID(), stars: 0)
        row.id = id
        return row
    }

    func householdFingerprint() -> String {
        HouseholdFingerprint.compute([hotelId.uuidString, guestId.uuidString, String(stars)])
    }

    func populateHouseholdFields(on record: CKRecord) {
        record["hotelId"] = hotelId.uuidString
        record["guestId"] = guestId.uuidString
        record["stars"] = stars
    }

    func applyHouseholdFields(from record: CKRecord) {
        hotelId = UUID(uuidString: record["hotelId"] as? String ?? "") ?? UUID()
        guestId = UUID(uuidString: record["guestId"] as? String ?? "") ?? UUID()
        stars = record["stars"] as? Int ?? 0
    }
}

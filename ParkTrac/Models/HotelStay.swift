import Foundation
import SwiftData

@Model
final class HotelStay {
    var id: UUID = UUID()
    var hotelName: String = ""
    var resort: String = ""
    var tier: String = ""
    var isVisited: Bool = false
    var checkIn: Date?
    var checkOut: Date?
    var roomType: String = ""
    var mattRating: Int = 0
    var wifeRating: Int = 0
    var notes: String = ""
    var syncUpdatedAt: Date = Date()
    @Attribute(.externalStorage) var photoData: [Data] = []

    // mattRating/wifeRating stay declared (unused by app logic) so RatingMigrationService
    // has legacy data to read once; real ratings now live in HotelRating rows.
    var averageRating: Double? {
        guard isVisited, let context = modelContext else { return nil }
        let hid = id
        let ratings = (try? context.fetch(FetchDescriptor<HotelRating>(
            predicate: #Predicate { $0.hotelId == hid }
        ))) ?? []
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.map(\.stars).reduce(0, +)) / Double(ratings.count)
    }

    var nightsStayed: Int? {
        guard let checkIn, let checkOut else { return nil }
        return Calendar.current.dateComponents([.day], from: checkIn, to: checkOut).day
    }

    init(hotelName: String, resort: String, tier: String) {
        self.id = UUID()
        self.hotelName = hotelName
        self.resort = resort
        self.tier = tier
        self.isVisited = false
        self.checkIn = nil
        self.checkOut = nil
        self.roomType = ""
        self.mattRating = 0
        self.wifeRating = 0
        self.notes = ""
        self.syncUpdatedAt = Date()
        self.photoData = []
    }
}

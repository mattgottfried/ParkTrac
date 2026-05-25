import Foundation
import SwiftData

@Model
final class HotelStay {
    var id: UUID
    var hotelName: String
    var resort: String
    var tier: String
    var isVisited: Bool
    var checkIn: Date?
    var checkOut: Date?
    var roomType: String
    var mattRating: Int
    var wifeRating: Int
    var notes: String
    @Attribute(.externalStorage) var photoData: [Data]

    var averageRating: Double? {
        guard isVisited, mattRating > 0, wifeRating > 0 else { return nil }
        return Double(mattRating + wifeRating) / 2.0
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
        self.photoData = []
    }
}

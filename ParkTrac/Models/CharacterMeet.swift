import Foundation
import SwiftData

/// One character seeded from `allCharacterAppearances` (`CharacterData.swift`) or added by hand —
/// a Bucket-List-style checklist entry, not a per-visit log (see `BucketListService` for the
/// insert-only seeding pattern this mirrors).
@Model
final class CharacterMeet {
    var id: UUID = UUID()
    var character: String = ""
    var park: String = ""
    var resort: String = ""
    /// Where in the park to find them, copied from the seed data for reference
    var location: String = ""
    var isMet: Bool = false
    var metDate: Date?
    var notes: String = ""
    @Attribute(.externalStorage) var photoData: [Data] = []

    init(
        character: String,
        park: String,
        resort: String,
        location: String = "",
        isMet: Bool = false
    ) {
        self.id = UUID()
        self.character = character
        self.park = park
        self.resort = resort
        self.location = location
        self.isMet = isMet
        self.metDate = nil
        self.notes = ""
        self.photoData = []
    }
}

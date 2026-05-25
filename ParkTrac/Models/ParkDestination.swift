import Foundation

enum ParkGroup: String, CaseIterable, Identifiable {
    case disney = "Walt Disney World"
    case universal = "Universal Orlando"

    var id: String { rawValue }

    var parks: [Park] {
        switch self {
        case .disney:
            return [
                Park(id: "75ea578a-adc8-4116-a54d-dccb60765ef9", name: "Magic Kingdom"),
                Park(id: "47f90d2c-e191-4239-a466-5892ef59a88b", name: "EPCOT"),
                Park(id: "288747d1-8b4f-4a64-867e-ea7c9b27bad8", name: "Hollywood Studios"),
                Park(id: "1c84a229-8862-4648-9c71-378ddd2c7693", name: "Animal Kingdom"),
            ]
        case .universal:
            return [
                Park(id: "9a245984-2824-4c4f-b5b9-dc4041d503af", name: "Universal Studios Florida"),
                Park(id: "267615cc-8943-4522-b299-4b2de2bc8c14", name: "Islands of Adventure"),
                Park(id: "b6700ea4-f9c4-4b7c-b7a1-a26e24a97fd3", name: "Epic Universe"),
            ]
        }
    }

    var allParkNames: [String] {
        parks.map(\.name)
    }
}

struct Park: Identifiable, Hashable {
    let id: String
    let name: String
}

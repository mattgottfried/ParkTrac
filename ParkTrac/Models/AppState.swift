import SwiftUI
import Observation

@Observable
final class AppState {
    var selectedResort: ParkGroup {
        didSet { UserDefaults.standard.set(selectedResort.rawValue, forKey: "selectedResortRaw") }
    }
    var showResortPicker: Bool = false

    // MARK: - Persisted Settings

    var defaultMapIsSatellite: Bool {
        didSet { UserDefaults.standard.set(defaultMapIsSatellite, forKey: "defaultMapIsSatellite") }
    }
    var sortRidesAlphabetically: Bool {
        didSet { UserDefaults.standard.set(sortRidesAlphabetically, forKey: "sortRidesAlphabetically") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedResortRaw") ?? ""
        self.selectedResort    = ParkGroup(rawValue: saved) ?? .disney
        self.defaultMapIsSatellite   = UserDefaults.standard.bool(forKey: "defaultMapIsSatellite")
        self.sortRidesAlphabetically = UserDefaults.standard.bool(forKey: "sortRidesAlphabetically")
    }
}

import WidgetKit
import AppIntents

enum WidgetResortChoice: String, AppEnum {
    case disney
    case universal

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Resort"
    static var caseDisplayRepresentations: [WidgetResortChoice: DisplayRepresentation] = [
        .disney: "Walt Disney World",
        .universal: "Universal Orlando"
    ]

    var parkGroup: ParkGroup {
        switch self {
        case .disney: return .disney
        case .universal: return .universal
        }
    }
}

struct WaitTimeWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Wait Times"
    static var description = IntentDescription("Shows live wait times for a resort.")

    @Parameter(title: "Resort", default: .disney)
    var resort: WidgetResortChoice

    func perform() async throws -> some IntentResult {
        .result()
    }
}

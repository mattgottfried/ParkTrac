import SwiftUI
import SwiftData

struct ParkComparisonView: View {
    let parkName: String
    let parkId: String
    let currentAvgWait: Double
    @Environment(\.modelContext) private var modelContext
    @State private var comparison: Double?

    var body: some View {
        Group {
            if let pct = comparison {
                let busier = pct > 0
                let absPct = Int(abs(pct).rounded())
                Label(
                    "\(absPct)% \(busier ? "busier" : "lighter") than usual",
                    systemImage: busier ? "arrow.up" : "arrow.down"
                )
                .font(.caption2)
                .foregroundStyle(busier ? .orange : .green)
            }
        }
        .task { recompute() }
        .onChange(of: currentAvgWait) { recompute() }
    }

    private func recompute() {
        comparison = WaitTimePredictionService.parkComparison(
            parkName: parkName,
            parkId: parkId,
            currentAvgWait: currentAvgWait,
            context: modelContext
        )
    }
}

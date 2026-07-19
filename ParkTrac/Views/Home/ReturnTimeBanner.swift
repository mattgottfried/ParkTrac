import SwiftUI
import SwiftData

struct ReturnTimeBanner: View {
    @Query(sort: \PlanItem.sortOrder) private var allItems: [PlanItem]
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @State private var now = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var urgentPasses: [PlanItem] {
        let resort = appState.selectedResort.rawValue
        let today = Calendar.current.startOfDay(for: now)
        return allItems.filter { item in
            guard (item.kind == "ll" || item.kind == "aap") && !item.isDone else { return false }
            guard item.resort == resort else { return false }
            guard Calendar.current.isDate(item.date, inSameDayAs: today) else { return false }
            guard let end = item.llReturnEnd, end != .distantFuture else { return false }
            let minsLeft = end.timeIntervalSince(now) / 60
            return minsLeft > 0 && minsLeft <= 15   // within 15 min of closing
        }
    }

    var body: some View {
        ForEach(urgentPasses) { pass in
            if let end = pass.llReturnEnd {
                let minsLeft = Int(end.timeIntervalSince(now) / 60)
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 14, weight: .semibold))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(pass.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("Return window closes in \(minsLeft) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation { pass.isDone = true }
                        try? context.save()
                        NotificationService.shared.cancelLLReminder(passId: pass.id.uuidString)
                    } label: {
                        Text("Done")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(minsLeft <= 5 ? Color.red : Color.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(minsLeft <= 5 ? Color.red.opacity(0.12) : Color.orange.opacity(0.1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(ticker) { now = $0 }
        .animation(.spring(response: 0.35), value: urgentPasses.map(\.id))
    }
}

import SwiftUI

struct ShowsListView: View {
    let shows: [DisplayShow]
    let theme: ParkTheme

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        if shows.isEmpty {
            ContentUnavailableView("No Shows", systemImage: "theatermasks",
                description: Text("No entertainment scheduled or show times unavailable."))
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(shows) { show in
                        ShowRowView(show: show, theme: theme, timeFmt: Self.timeFmt)
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
    }
}

private struct ShowRowView: View {
    let show: DisplayShow
    let theme: ParkTheme
    let timeFmt: DateFormatter

    private var nextLabel: String {
        guard let next = show.nextShowtime else { return show.statusDisplay }
        let interval = next.timeIntervalSinceNow
        if interval < 0 { return "Ended" }
        if interval < 60 { return "Starting now" }
        let mins = Int(interval / 60)
        if mins < 60 { return "In \(mins) min" }
        let hrs = mins / 60; let rem = mins % 60
        return rem == 0 ? "In \(hrs)h" : "In \(hrs)h \(rem)m"
    }

    private var nextColor: Color {
        guard let next = show.nextShowtime else { return .secondary }
        let interval = next.timeIntervalSinceNow
        if interval < 0 { return .secondary }
        if interval < 300 { return .red }
        if interval < 900 { return .orange }
        return .green
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(show.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let next = show.nextShowtime {
                    Text(timeFmt.string(from: next))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(nextLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(nextColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(nextColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

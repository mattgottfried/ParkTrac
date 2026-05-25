import SwiftUI

struct RideRowView: View {
    let entry: LiveDataEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                if !entry.isOperating {
                    Text(entry.statusDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            WaitBadgeView(entry: entry)
        }
        .padding(.vertical, 4)
        .opacity(entry.isOperating ? 1.0 : 0.5)
    }
}

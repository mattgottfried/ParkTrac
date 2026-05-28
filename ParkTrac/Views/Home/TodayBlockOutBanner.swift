import SwiftUI

struct TodayBlockOutBanner: View {
    let appState: AppState
    @State private var showCalendar = false

    private var disneyBlocked: Bool {
        guard appState.disneyPassTier != .none else { return false }
        return BlockOutService.isBlockedOut(Date(), disney: appState.disneyPassTier)
    }
    private var universalBlocked: Bool {
        guard appState.universalPassTier != .none else { return false }
        return BlockOutService.isBlockedOut(Date(), universal: appState.universalPassTier)
    }
    private var hasAnyPass: Bool {
        appState.disneyPassTier != .none || appState.universalPassTier != .none
    }

    var body: some View {
        if hasAnyPass {
            Button { showCalendar = true } label: {
                bannerContent
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showCalendar) {
                NavigationStack {
                    CrowdCalendarView(resort: appState.selectedResort)
                        .navigationTitle("Calendar")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showCalendar = false } } }
                }
            }
        }
    }

    private var bannerContent: some View {
        HStack(spacing: 10) {
            if !disneyBlocked && !universalBlocked {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Both passes open today").font(.caption.weight(.semibold))
                    Text(passNames).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "nosign").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    if disneyBlocked { Text("Disney \(appState.disneyPassTier.rawValue) — blocked today").font(.caption.weight(.semibold)).foregroundStyle(.red) }
                    if universalBlocked { Text("Universal \(appState.universalPassTier.rawValue) — blocked today").font(.caption.weight(.semibold)).foregroundStyle(.red) }
                    if !disneyBlocked && appState.disneyPassTier != .none { Text("Disney — open").font(.caption2).foregroundStyle(.green) }
                    if !universalBlocked && appState.universalPassTier != .none { Text("Universal — open").font(.caption2).foregroundStyle(.green) }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var passNames: String {
        var parts: [String] = []
        if appState.disneyPassTier != .none { parts.append("Disney \(appState.disneyPassTier.rawValue)") }
        if appState.universalPassTier != .none { parts.append("Universal \(appState.universalPassTier.rawValue)") }
        return parts.joined(separator: " · ")
    }
}

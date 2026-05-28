import SwiftUI

struct CharacterFinderView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var resort: String { appState.selectedResort.rawValue }

    private var filtered: [CharacterAppearance] {
        allCharacterAppearances
            .filter { $0.resort == resort }
            .filter { searchText.isEmpty ||
                $0.character.localizedCaseInsensitiveContains(searchText) ||
                $0.park.localizedCaseInsensitiveContains(searchText) ||
                $0.location.localizedCaseInsensitiveContains(searchText) }
    }

    private var grouped: [(park: String, items: [CharacterAppearance])] {
        let parks = filtered.map(\.park)
        let unique = Array(NSOrderedSet(array: parks)) as? [String] ?? []
        return unique.map { park in (park, filtered.filter { $0.park == park }) }
    }

    var body: some View {
        List {
            Section {
                Text("Times are approximate and change daily. Always check the official Disney/Universal app or Guest Services for the current schedule.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(grouped, id: \.park) { group in
                Section(group.park) {
                    ForEach(group.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.character).font(.subheadline.weight(.semibold))
                            HStack(spacing: 4) {
                                Image(systemName: "mappin").font(.caption2).foregroundStyle(.secondary)
                                Text(item.location).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary)
                                Text(item.typicalTimes).font(.caption).foregroundStyle(.secondary)
                            }
                            if !item.notes.isEmpty {
                                Text(item.notes).font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if grouped.isEmpty {
                ContentUnavailableView("No Characters Found", systemImage: "figure.wave",
                    description: Text("Try a different search."))
            }
        }
        .searchable(text: $searchText, prompt: "Search characters or parks")
        .navigationTitle("Character Finder")
    }
}

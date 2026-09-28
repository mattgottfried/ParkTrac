import SwiftUI
import SwiftData
import PhotosUI

/// Bucket List → Characters: a checklist of character meet-and-greets, seeded from
/// `allCharacterAppearances` (`CharacterData.swift`) the same way restaurants and hotels are
/// seeded — insert-only, keyed by character + park, so custom entries always survive.
struct CharacterMeetListView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \CharacterMeet.character) private var allCharacters: [CharacterMeet]
    @State private var searchText: String = ""
    @State private var selected: CharacterMeet?
    @State private var metFilter: BucketVisitedFilter = .all
    @State private var showAddSheet = false

    private var resortCharacters: [CharacterMeet] {
        allCharacters.filter { $0.resort == appState.selectedResort.rawValue }
    }

    private var filtered: [CharacterMeet] {
        resortCharacters
            .filter { searchText.isEmpty || $0.character.localizedCaseInsensitiveContains(searchText) }
            .filter {
                switch metFilter {
                case .all: return true
                case .visited: return $0.isMet
                case .notVisited: return !$0.isMet
                }
            }
    }

    private var hasActiveFilters: Bool { metFilter != .all }

    var body: some View {
        VStack(spacing: 0) {
            BucketProgressView(
                visited: resortCharacters.filter(\.isMet).count,
                total: resortCharacters.count,
                label: "Characters Met",
                color: .purple
            )
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Group {
                if !searchText.isEmpty && filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if resortCharacters.isEmpty {
                    // Nothing at this resort yet (the seeded list is Orlando-only)
                    ContentUnavailableView {
                        Label("No Characters Yet", systemImage: "star.circle")
                    } description: {
                        Text("Add the characters you want to meet at \(appState.selectedResort.shortName).")
                    } actions: {
                        Button("Add Character") { showAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No characters match the current filter.")
                    } actions: {
                        Button("Clear Filters") { metFilter = .all }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered) { character in
                            CharacterMeetRow(character: character)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = character }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search characters")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $metFilter) {
                        ForEach(BucketVisitedFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add character")
            }
        }
        .sheet(item: $selected) { CharacterMeetDetailView(character: $0) }
        .sheet(isPresented: $showAddSheet) {
            AddCharacterMeetSheet(resort: appState.selectedResort.rawValue)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct CharacterMeetRow: View {
    let character: CharacterMeet

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: character.isMet ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(character.isMet ? Color.green : Color.secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(character.character)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(character.isMet, color: .secondary)
                HStack(spacing: 6) {
                    Text(character.park)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !character.location.isEmpty {
                        Text("·").foregroundStyle(.secondary)
                        Text(character.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if character.isMet, let date = character.metDate {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !character.photoData.isEmpty {
                Image(systemName: "photo.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct CharacterMeetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let character: CharacterMeet

    @State private var isMet: Bool
    @State private var metDate: Date
    @State private var notes: String
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage]
    @State private var photosChanged = false

    init(character: CharacterMeet) {
        self.character = character
        _isMet = State(initialValue: character.isMet)
        _metDate = State(initialValue: character.metDate ?? .now)
        _notes = State(initialValue: character.notes)
        _photoImages = State(initialValue: character.photoData.compactMap { UIImage(data: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(character.character).font(.headline)
                        Text(character.park).font(.caption).foregroundStyle(.secondary)
                        if !character.location.isEmpty {
                            Text(character.location).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Met") {
                    Toggle("Met This Character", isOn: $isMet)
                    if isMet {
                        DatePicker("Date", selection: $metDate, displayedComponents: .date)
                    }
                }

                if isMet {
                    Section("Notes") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                    }

                    Section("Photos") {
                        if !photoImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(photoImages.indices, id: \.self) { i in
                                        Image(uiImage: photoImages[i])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        PhotosPicker(selection: $selectedPhotos, matching: .images) {
                            Label("Add Photos", systemImage: "photo.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onChange(of: selectedPhotos) { _, newItems in
                Task { await loadPhotos(from: newItems) }
            }
        }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                photoImages.append(image)
                photosChanged = true
            }
        }
        selectedPhotos = []
    }

    private func save() {
        character.isMet = isMet
        character.metDate = isMet ? metDate : nil
        character.notes = notes
        if photosChanged {
            character.photoData = photoImages.compactMap { $0.jpegData(compressionQuality: 0.7) }
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Add Custom Character

private struct AddCharacterMeetSheet: View {
    let resort: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var character = ""
    @State private var park = ""
    @State private var location = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $character)
                    TextField("Park", text: $park)
                    TextField("Location (optional)", text: $location)
                } header: {
                    Text("Character")
                } footer: {
                    Text("Added to your \(resort) character checklist.")
                }
            }
            .navigationTitle("Add Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(character.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let meet = CharacterMeet(
            character: character.trimmingCharacters(in: .whitespaces),
            park: park.trimmingCharacters(in: .whitespaces),
            resort: resort,
            location: location.trimmingCharacters(in: .whitespaces)
        )
        context.insert(meet)
        try? context.save()
        dismiss()
    }
}

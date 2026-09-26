import SwiftUI
import MapKit
import PhotosUI

/// Save where you parked, then find your way back. Opened from the map's car button,
/// My Day, the car pin, or `thrilltrack://parking`.
struct ParkingSheet: View {
    let resort: ParkGroup

    @Environment(\.dismiss) private var dismiss
    @Environment(WaitTimesViewModel.self) private var viewModel
    @AppStorage(ParkingReminder.enabledKey) private var remindBeforeClose = true
    @State private var parking = ParkingService.shared
    @State private var locationService = LocationService()

    @State private var note = ""
    // Lot menus (like the Disney app); "" = not picked
    @State private var lotName = ""
    @State private var sectionName = ""
    @State private var level = 0
    @State private var row = ""
    @State private var isLocating = false
    @State private var locateError: String?
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPhoto: UIImage?
    @State private var showClearConfirm = false
    @State private var showFullPhoto = false
    private enum Field { case note, row }
    @FocusState private var focused: Field?

    private var spot: ParkingSpot? { parking.spot(for: resort) }
    private var lots: [ParkingLot] { ParkingLots.lots(for: resort) }
    private var selectedLot: ParkingLot? { lots.first { $0.name == lotName } }
    private var lastLotKey: String { "lastParkingLot_\(RideMetadata.normalize(resort.rawValue))" }

    /// What the menus currently say
    private var details: ParkingDetails {
        guard let lot = selectedLot else { return .empty }
        return ParkingDetails(lot: lot.name,
                              section: lot.allSections.contains(sectionName) ? sectionName : nil,
                              level: lot.levels != nil && level > 0 ? level : nil,
                              row: row).normalized
    }

    private var hasAnythingToSave: Bool {
        !details.isEmpty || !note.trimmingCharacters(in: .whitespaces).isEmpty || pendingPhoto != nil
    }
    private var photo: UIImage? { pendingPhoto ?? parking.photo(for: resort) }

    var body: some View {
        NavigationStack {
            Form {
                if let spot {
                    savedSections(spot)
                } else {
                    saveSections
                }
            }
            .navigationTitle(spot == nil ? "Save Parking Spot" : "My Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { commitNote(); dismiss() }
                }
            }
            .onAppear {
                note = spot?.note ?? ""
                if let d = spot?.details, !d.isEmpty {
                    lotName = d.lot ?? ""
                    sectionName = d.section ?? ""
                    level = d.level ?? 0
                    row = d.row ?? ""
                } else if let last = UserDefaults.standard.string(forKey: lastLotKey),
                          lots.contains(where: { $0.name == last }) {
                    lotName = last   // usually the same lot as last time
                }
                locationService.requestAndStart()
            }
            .onChange(of: lotName) { _, name in
                if let lot = selectedLot {
                    if !lot.allSections.contains(sectionName) { sectionName = "" }
                    if lot.levels == nil { level = 0 }
                    UserDefaults.standard.set(name, forKey: lastLotKey)
                }
                commitDetails()
            }
            .onChange(of: sectionName) { _, _ in commitDetails() }
            .onChange(of: level) { _, _ in commitDetails() }
            .onChange(of: focused) { old, _ in
                if old == .note { commitNote() }
                if old == .row { commitDetails() }
            }
            .onDisappear { locationService.stop() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        applyPhoto(image)
                    }
                    photoItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in applyPhoto(image) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showFullPhoto) {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit()
                        .presentationDragIndicator(.visible)
                }
            }
            .confirmationDialog("Clear parking spot?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear Spot", role: .destructive) {
                    parking.clear(resort: resort)
                    ParkingReminder.cancel(resort: resort)
                    note = ""
                    sectionName = ""
                    level = 0
                    row = ""
                    pendingPhoto = nil
                }
            } message: {
                Text("Removes it from your other devices too.")
            }
        }
    }

    // MARK: Not saved yet

    @ViewBuilder
    private var saveSections: some View {
        Section {
            Button {
                Task { await saveHere() }
            } label: {
                HStack {
                    Label(isLocating ? "Finding your exact spot…" : "Save Spot Here", systemImage: "car.fill")
                        .font(.headline)
                    Spacer()
                    if isLocating { ProgressView() }
                }
            }
            .disabled(isLocating)
            if let locateError {
                Text(locateError).font(.caption).foregroundStyle(.orange)
            }
            if hasAnythingToSave && !isLocating {
                Button {
                    locateError = nil
                    saveWithoutLocation()
                } label: {
                    Label(details.isEmpty ? "Save Without GPS" : "Save Section & Row Only", systemImage: "square.and.arrow.down")
                }
            }
        } footer: {
            Text("Save it while you're standing by the car — ThrillTrack uses your phone's GPS for walking directions. Or just pick the lot, section and row. It syncs to your other devices signed in to the same iCloud account.")
        }

        noteAndPhotoSections
    }

    // MARK: Saved

    @ViewBuilder
    private func savedSections(_ spot: ParkingSpot) -> some View {
        Section {
            if let coordinate = spot.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400))) {
                    Marker(spot.title, systemImage: "car.fill", coordinate: coordinate)
                        .tint(.blue)
                    UserAnnotation()
                }
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
                .accessibilityLabel("Map showing your car")

                if let me = locationService.userCoordinate {
                    Label(ParkingDistance.describe(meters: ParkingDistance.meters(from: me, to: coordinate)),
                          systemImage: "figure.walk")
                }
                Button {
                    commitNote()
                    commitDetails()
                    ParkingService.openWalkingDirections(to: spot)
                } label: {
                    Label("Walk There in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.headline)
                }
            } else {
                Label("No GPS location saved — find it by the section and row below.", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Saved \(spot.savedAt.formatted(date: .omitted, time: .shortened))")
        }

        noteAndPhotoSections

        Section {
            Button {
                Task { await saveHere() }
            } label: {
                HStack {
                    Label(isLocating ? "Finding your exact spot…" : "Move Spot to Here", systemImage: "location.fill")
                    Spacer()
                    if isLocating { ProgressView() }
                }
            }
            .disabled(isLocating)
            if let locateError {
                Text(locateError).font(.caption).foregroundStyle(.orange)
            }
            Button("Clear Spot", role: .destructive) { showClearConfirm = true }
        }

        Section {
            Toggle(isOn: $remindBeforeClose) {
                Label("Remind Me Before Parks Close", systemImage: "bell.badge")
            }
            .onChange(of: remindBeforeClose) { _, _ in refreshReminder() }
        } footer: {
            Text("A notification 30 minutes before the last park closes, with your car's spot.")
        }
    }

    // MARK: Note + photo

    @ViewBuilder
    private var noteAndPhotoSections: some View {
        if !lots.isEmpty {
            Section {
                Picker("Lot", selection: $lotName) {
                    Text("Choose…").tag("")
                    ForEach(lots) { Text($0.name).tag($0.name) }
                }
                if let lot = selectedLot {
                    Picker("Section", selection: $sectionName) {
                        Text("Choose…").tag("")
                        ForEach(Array(lot.groups.enumerated()), id: \.offset) { _, group in
                            if let groupName = group.name {
                                Section(groupName) {
                                    ForEach(group.sections, id: \.self) { Text($0).tag($0) }
                                }
                            } else {
                                ForEach(group.sections, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                    if let levels = lot.levels {
                        Picker("Level", selection: $level) {
                            Text("—").tag(0)
                            ForEach(Array(levels), id: \.self) { Text("Level \($0)").tag($0) }
                        }
                    }
                    HStack {
                        Text(lot.rowLabel.isEmpty ? "Number" : lot.rowLabel)
                        TextField(lot.rowPrompt, text: $row)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focused, equals: .row)
                            .submitLabel(.done)
                            .onSubmit(commitDetails)
                    }
                }
            } header: {
                Text("Where You Parked")
            } footer: {
                Text("The lot, the character or name on the sign, and your row — like the Disney and Universal apps.")
            }
        }

        Section(lots.isEmpty ? "Lot / Row" : "Notes") {
            TextField(lots.isEmpty ? "e.g. P3, Level 2, Row C" : "Anything else (optional)", text: $note)
                .focused($focused, equals: .note)
                .submitLabel(.done)
                .onSubmit(commitNote)
        }

        Section {
            if let photo {
                Button { showFullPhoto = true } label: {
                    Image(uiImage: photo)
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 180)
                        .clipped()
                }
                .listRowInsets(EdgeInsets())
                .accessibilityLabel("Parking photo. Tap to enlarge.")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label(photo == nil ? "Take Photo of Row Sign" : "Retake Photo", systemImage: "camera.fill")
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose from Library", systemImage: "photo")
            }
            if photo != nil {
                Button("Remove Photo", role: .destructive) {
                    pendingPhoto = nil
                    parking.setPhoto(nil, resort: resort)
                }
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("The photo stays on this phone.")
        }
    }

    // MARK: Actions

    @MainActor
    private func saveHere() async {
        locateError = nil
        isLocating = true
        defer { isLocating = false }
        do {
            let locator = PreciseLocator()
            let location = try await locator.locate()
            if spot == nil {
                parking.save(coordinate: location.coordinate, note: note, details: details, resort: resort)
            } else {
                parking.updateLocation(location.coordinate, resort: resort)
            }
            if let pendingPhoto {
                parking.setPhoto(pendingPhoto, resort: resort)
                self.pendingPhoto = nil
            }
            refreshReminder()
        } catch PreciseLocator.Failure.denied {
            locateError = hasAnythingToSave
                ? "Location is off for ThrillTrack. Saved what you entered — turn location on in Settings for walking directions."
                : "Location is off for ThrillTrack. Pick your lot, section and row instead, or turn location on in Settings."
            saveWithoutLocationIfNeeded()
        } catch {
            locateError = hasAnythingToSave
                ? "Couldn't get a GPS fix. Saved what you entered — try again in the open."
                : "Couldn't get a GPS fix. Pick your lot, section and row, or try again in the open."
            saveWithoutLocationIfNeeded()
        }
    }

    /// No GPS: still keep the section/row, note and photo so the spot isn't lost
    private func saveWithoutLocationIfNeeded() {
        guard spot == nil, hasAnythingToSave else { return }
        saveWithoutLocation()
    }

    private func saveWithoutLocation() {
        parking.save(coordinate: nil, note: note, details: details, resort: resort)
        if let pendingPhoto {
            parking.setPhoto(pendingPhoto, resort: resort)
            self.pendingPhoto = nil
        }
        refreshReminder()
    }

    private func commitNote() {
        guard spot != nil, note != spot?.note else { return }
        parking.updateNote(note, resort: resort)
        refreshReminder()   // the reminder quotes the note
    }

    private func commitDetails() {
        guard let spot, details != spot.details.normalized else { return }
        parking.updateDetails(details, resort: resort)
        refreshReminder()   // the reminder quotes the spot
    }

    private func refreshReminder() {
        if remindBeforeClose {
            Task { await NotificationService.shared.requestAuthorization() }
        }
        ParkingReminder.refresh(resort: resort, schedule: viewModel.todaySchedule(forResort: resort))
    }

    private func applyPhoto(_ image: UIImage) {
        if spot == nil {
            pendingPhoto = image   // saved with the spot
        } else {
            parking.setPhoto(image, resort: resort)
        }
    }
}

// MARK: - Camera

/// UIImagePickerController wrapper — PhotosPicker can't open the camera.
private struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

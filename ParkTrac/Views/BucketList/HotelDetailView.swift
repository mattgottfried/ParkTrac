import SwiftUI
import SwiftData
import PhotosUI

struct HotelDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Guest.name) private var allGuests: [Guest]
    let hotel: HotelStay

    @State private var isVisited: Bool
    @State private var checkIn: Date
    @State private var checkOut: Date
    @State private var roomType: String
    @State private var ratings: [UUID: Int] = [:]
    @State private var showGuestPicker = false
    @State private var notes: String
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []
    @State private var photosChanged = false

    init(hotel: HotelStay) {
        self.hotel = hotel
        _isVisited = State(initialValue: hotel.isVisited)
        _checkIn = State(initialValue: hotel.checkIn ?? .now)
        _checkOut = State(initialValue: hotel.checkOut ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        _roomType = State(initialValue: hotel.roomType)
        _notes = State(initialValue: hotel.notes)
        _photoImages = State(initialValue: hotel.photoData.compactMap { UIImage(data: $0) })
    }

    private func ratingBinding(for guest: Guest) -> Binding<Int> {
        Binding(
            get: { ratings[guest.id] ?? HotelRating.current(hotelId: hotel.id, guestId: guest.id, context: context) },
            set: { ratings[guest.id] = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hotel.hotelName).font(.headline)
                        HStack {
                            Text(hotel.resort).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(hotel.tier)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tierColor.opacity(0.15))
                                .foregroundStyle(tierColor)
                                .clipShape(Capsule())
                        }
                    }
                }

                Section("Stay") {
                    Toggle("Stayed Here", isOn: $isVisited)
                    if isVisited {
                        DatePicker("Check-In", selection: $checkIn, displayedComponents: .date)
                        DatePicker("Check-Out", selection: $checkOut, in: checkIn..., displayedComponents: .date)
                        TextField("Room Type", text: $roomType)
                    }
                }

                if isVisited {
                    Section {
                        ForEach(allGuests) { guest in
                            StarRatingView(label: guest.name, rating: ratingBinding(for: guest))
                        }
                        Button {
                            showGuestPicker = true
                        } label: {
                            Label("Add Guest", systemImage: "person.badge.plus")
                        }
                    } header: {
                        Text("Ratings")
                    }

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
            .navigationTitle("Hotel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                }
            }
            .onChange(of: selectedPhotos) { _, newItems in
                Task { await loadPhotos(from: newItems) }
            }
            .sheet(isPresented: $showGuestPicker) {
                GuestPickerSheet()
            }
        }
    }

    private var tierColor: Color {
        switch hotel.tier {
        case "Deluxe", "Premier":    return .purple
        case "Disney Vacation Club": return .blue
        case "Preferred":            return .green
        case "Moderate", "Standard": return .orange
        default:                     return .gray
        }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        // Append so newly picked photos join the already-saved ones
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                photoImages.append(image)
                photosChanged = true
            }
        }
        selectedPhotos = []
    }

    private func save() async {
        hotel.isVisited = isVisited
        hotel.checkIn = isVisited ? checkIn : nil
        hotel.checkOut = isVisited ? checkOut : nil
        hotel.roomType = roomType
        if isVisited {
            for guest in allGuests {
                // Fall back to the persisted value (not 0) for guests whose star row the
                // user never touched this session — otherwise saving would silently wipe
                // out every untouched guest's existing rating.
                let stars = ratings[guest.id]
                    ?? HotelRating.current(hotelId: hotel.id, guestId: guest.id, context: context)
                HotelRating.set(hotelId: hotel.id, guestId: guest.id, stars: stars, context: context)
            }
        } else {
            HotelRating.deleteAll(hotelId: hotel.id, context: context)
        }
        hotel.notes = notes
        // Re-encode only when photos changed — repeated JPEG passes degrade quality
        if photosChanged {
            hotel.photoData = photoImages.compactMap { $0.jpegData(compressionQuality: 0.7) }
        }
        try? context.save()
        dismiss()
    }
}

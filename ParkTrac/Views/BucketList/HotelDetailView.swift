import SwiftUI
import PhotosUI

struct HotelDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let hotel: HotelStay

    @State private var isVisited: Bool
    @State private var checkIn: Date
    @State private var checkOut: Date
    @State private var roomType: String
    @State private var mattRating: Int
    @State private var heatherRating: Int
    @State private var notes: String
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []

    init(hotel: HotelStay) {
        self.hotel = hotel
        _isVisited = State(initialValue: hotel.isVisited)
        _checkIn = State(initialValue: hotel.checkIn ?? .now)
        _checkOut = State(initialValue: hotel.checkOut ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        _roomType = State(initialValue: hotel.roomType)
        _mattRating = State(initialValue: hotel.mattRating)
        _heatherRating = State(initialValue: hotel.wifeRating)
        _notes = State(initialValue: hotel.notes)
        _photoImages = State(initialValue: hotel.photoData.compactMap { UIImage(data: $0) })
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
                    Section("Ratings") {
                        StarRatingView(label: "Matt", rating: $mattRating)
                        StarRatingView(label: "Heather", rating: $heatherRating)
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
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        photoImages = loaded
    }

    private func save() async {
        hotel.isVisited = isVisited
        hotel.checkIn = isVisited ? checkIn : nil
        hotel.checkOut = isVisited ? checkOut : nil
        hotel.roomType = roomType
        hotel.mattRating = isVisited ? mattRating : 0
        hotel.wifeRating = isVisited ? heatherRating : 0
        hotel.notes = notes
        if !selectedPhotos.isEmpty {
            hotel.photoData = photoImages.compactMap { $0.jpegData(compressionQuality: 0.7) }
        }
        dismiss()
    }
}

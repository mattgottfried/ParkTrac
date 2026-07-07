import SwiftUI
import SwiftData
import PhotosUI

struct BucketRestaurantDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let restaurant: BucketRestaurant

    @State private var isVisited: Bool
    @State private var visitDate: Date
    @State private var mattRating: Int
    @State private var heatherRating: Int
    @State private var notes: String
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage]
    @State private var photosChanged = false

    init(restaurant: BucketRestaurant) {
        self.restaurant = restaurant
        _isVisited = State(initialValue: restaurant.isVisited)
        _visitDate = State(initialValue: restaurant.visitDate ?? .now)
        _mattRating = State(initialValue: Int(restaurant.mattRating.rounded()))
        _heatherRating = State(initialValue: Int(restaurant.wifeRating.rounded()))
        _notes = State(initialValue: restaurant.notes)
        _photoImages = State(initialValue: restaurant.photoData.compactMap { UIImage(data: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(restaurant.name).font(.headline)
                            Text(restaurant.park).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(restaurant.category)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(categoryColor.opacity(0.15))
                            .foregroundStyle(categoryColor)
                            .clipShape(Capsule())
                    }
                }

                Section("Visit") {
                    Toggle("Visited", isOn: $isVisited)
                    if isVisited {
                        DatePicker("Date", selection: $visitDate, displayedComponents: .date)
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
            .navigationTitle("Restaurant")
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

    private var categoryColor: Color {
        switch restaurant.category {
        case "Signature Dining": return .purple
        case "Character Dining": return .blue
        case "Table Service":    return .green
        case "Dinner Show":      return .orange
        default:                 return .gray
        }
    }

    private func save() {
        restaurant.isVisited = isVisited
        restaurant.visitDate = isVisited ? visitDate : nil
        if isVisited {
            // The stars edit whole numbers but the model stores halves (e.g. 4.5
            // from seed data) — only overwrite a rating the user actually changed
            if mattRating != Int(restaurant.mattRating.rounded()) {
                restaurant.mattRating = Double(mattRating)
            }
            if heatherRating != Int(restaurant.wifeRating.rounded()) {
                restaurant.wifeRating = Double(heatherRating)
            }
        } else {
            restaurant.mattRating = 0
            restaurant.wifeRating = 0
        }
        restaurant.notes = notes
        if photosChanged {
            restaurant.photoData = photoImages.compactMap { $0.jpegData(compressionQuality: 0.7) }
        }
        try? context.save()
        dismiss()
    }
}

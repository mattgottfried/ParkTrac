import SwiftUI
import SwiftData

struct BucketRestaurantDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let restaurant: BucketRestaurant

    @State private var isVisited: Bool
    @State private var visitDate: Date
    @State private var mattRating: Int
    @State private var heatherRating: Int
    @State private var notes: String

    init(restaurant: BucketRestaurant) {
        self.restaurant = restaurant
        _isVisited = State(initialValue: restaurant.isVisited)
        _visitDate = State(initialValue: restaurant.visitDate ?? .now)
        _mattRating = State(initialValue: Int(restaurant.mattRating.rounded()))
        _heatherRating = State(initialValue: Int(restaurant.wifeRating.rounded()))
        _notes = State(initialValue: restaurant.notes)
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
        }
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
        restaurant.mattRating = isVisited ? Double(mattRating) : 0
        restaurant.wifeRating = isVisited ? Double(heatherRating) : 0
        restaurant.notes = notes
        dismiss()
    }
}

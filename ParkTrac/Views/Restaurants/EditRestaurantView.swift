import SwiftUI
import SwiftData

struct EditRestaurantView: View {
    @Environment(\.dismiss) private var dismiss

    let restaurant: Restaurant

    @State private var name: String
    @State private var park: String
    @State private var dateVisited: Date
    @State private var notes: String
    @State private var mattRating: Int
    @State private var wifeRating: Int

    private let allParks: [(group: String, parks: [Park])] = ParkGroup.allCases.map {
        (group: $0.rawValue, parks: $0.parks)
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(restaurant: Restaurant) {
        self.restaurant = restaurant
        _name = State(initialValue: restaurant.name)
        _park = State(initialValue: restaurant.park)
        _dateVisited = State(initialValue: restaurant.dateVisited)
        _notes = State(initialValue: restaurant.notes)
        _mattRating = State(initialValue: restaurant.mattRating)
        _wifeRating = State(initialValue: restaurant.wifeRating)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Restaurant") {
                    TextField("Name", text: $name)
                }

                Section("Park") {
                    Picker("Park", selection: $park) {
                        ForEach(allParks, id: \.group) { entry in
                            Section(entry.group) {
                                ForEach(entry.parks) { p in
                                    Text(p.name).tag(p.name)
                                }
                            }
                        }
                    }
                    DatePicker("Date Visited", selection: $dateVisited, displayedComponents: .date)
                }

                Section("Ratings") {
                    StarRatingView(label: "Matt", rating: $mattRating)
                    StarRatingView(label: "Heather", rating: $wifeRating)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        restaurant.name = name.trimmingCharacters(in: .whitespaces)
        restaurant.park = park
        restaurant.dateVisited = dateVisited
        restaurant.notes = notes
        restaurant.mattRating = mattRating
        restaurant.wifeRating = wifeRating
        dismiss()
    }
}

import SwiftUI
import SwiftData

struct AddRestaurantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedPark = ParkGroup.disney.parks[0]
    @State private var dateVisited = Date.now
    @State private var notes = ""
    @State private var mattRating = 3
    @State private var wifeRating = 3

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Restaurant") {
                    TextField("Name", text: $name)
                }

                Section("Park") {
                    Picker("Resort", selection: $selectedPark) {
                        ForEach(ParkGroup.allCases) { group in
                            Section(group.rawValue) {
                                ForEach(group.parks) { park in
                                    Text(park.name).tag(park)
                                }
                            }
                        }
                    }
                    DatePicker("Date Visited", selection: $dateVisited, displayedComponents: .date)
                }

                Section("Ratings") {
                    StarRatingView(label: "Matt", rating: $mattRating)
                    StarRatingView(label: "Wife", rating: $wifeRating)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Add Restaurant")
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
        let restaurant = Restaurant(
            name: name.trimmingCharacters(in: .whitespaces),
            park: selectedPark.name,
            dateVisited: dateVisited,
            notes: notes,
            mattRating: mattRating,
            wifeRating: wifeRating
        )
        modelContext.insert(restaurant)
        dismiss()
    }
}

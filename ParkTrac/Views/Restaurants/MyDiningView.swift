import SwiftUI
import SwiftData

struct MyDiningView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \BucketRestaurant.name) private var all: [BucketRestaurant]
    @Query(sort: \DiningReservation.date) private var allReservations: [DiningReservation]

    @State private var selectedRestaurant: BucketRestaurant?
    @State private var showAddReservation = false

    private var resortVisited: [BucketRestaurant] {
        all
            .filter { $0.isVisited && $0.resort == appState.selectedResort.rawValue }
            .sorted { ($0.averageRating ?? 0) > ($1.averageRating ?? 0) }
    }

    private var resortTotal: Int {
        all.filter { $0.resort == appState.selectedResort.rawValue }.count
    }

    private var upcomingReservations: [DiningReservation] {
        let now = Date()
        return allReservations
            .filter { $0.resort == appState.selectedResort.rawValue && $0.date >= now && !$0.isCompleted }
            .sorted { $0.date < $1.date }
    }

    private var pastReservations: [DiningReservation] {
        let now = Date()
        return allReservations
            .filter { $0.resort == appState.selectedResort.rawValue && ($0.date < now || $0.isCompleted) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                // Upcoming Reservations section
                Section {
                    if upcomingReservations.isEmpty {
                        Text("No upcoming reservations")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(upcomingReservations) { res in
                            ReservationRow(reservation: res)
                        }
                        .onDelete { offsets in
                            deleteReservations(upcomingReservations, at: offsets)
                        }
                    }
                } header: {
                    HStack {
                        Text("Upcoming Reservations")
                        Spacer()
                        Button {
                            showAddReservation = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Past reservations (5 most recent, with link to full history)
                if !pastReservations.isEmpty {
                    Section("Past Reservations") {
                        ForEach(pastReservations.prefix(5)) { res in
                            ReservationRow(reservation: res)
                                .opacity(0.6)
                        }
                        .onDelete { offsets in
                            deleteReservations(Array(pastReservations.prefix(5)), at: offsets)
                        }

                        if pastReservations.count > 5 {
                            NavigationLink {
                                PastReservationsListView(resort: appState.selectedResort.rawValue)
                            } label: {
                                Text("See All (\(pastReservations.count))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                // Visited Restaurants
                Section {
                    BucketProgressView(
                        visited: resortVisited.count,
                        total: resortTotal,
                        label: "Restaurants Visited",
                        color: .orange
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    if resortVisited.isEmpty {
                        Text("Mark restaurants as visited in the Bucket List tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(resortVisited) { restaurant in
                            DiningRow(restaurant: restaurant)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedRestaurant = restaurant }
                        }
                    }
                } header: {
                    Text("Visited Restaurants")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("My Dining")
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $selectedRestaurant) { BucketRestaurantDetailView(restaurant: $0) }
            .sheet(isPresented: $showAddReservation) {
                AddReservationSheet(resort: appState.selectedResort.rawValue)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @Environment(\.modelContext) private var context

    private func deleteReservations(_ list: [DiningReservation], at offsets: IndexSet) {
        for index in offsets {
            context.delete(list[index])
        }
        try? context.save()
    }
}

// MARK: - Full Past Reservation History

private struct PastReservationsListView: View {
    let resort: String

    @Query(sort: \DiningReservation.date, order: .reverse) private var allReservations: [DiningReservation]
    @Environment(\.modelContext) private var context

    private var pastReservations: [DiningReservation] {
        let now = Date()
        return allReservations.filter { $0.resort == resort && ($0.date < now || $0.isCompleted) }
    }

    var body: some View {
        List {
            ForEach(pastReservations) { res in
                ReservationRow(reservation: res)
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(pastReservations[index])
                }
                try? context.save()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Past Reservations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}

// MARK: - Reservation Row

private struct ReservationRow: View {
    let reservation: DiningReservation

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(reservation.restaurantName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Self.dateFmt.string(from: reservation.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                // Party size
                Label("\(reservation.partySize)", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Confirmation number
                if !reservation.confirmationNumber.isEmpty {
                    Button {
                        UIPasteboard.general.string = reservation.confirmationNumber
                    } label: {
                        Label(reservation.confirmationNumber, systemImage: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !reservation.notes.isEmpty {
                Text(reservation.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Reservation Sheet

struct AddReservationSheet: View {
    let resort: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var restaurantName = ""
    @State private var restaurantPark = ""
    @State private var isAPEligible = true
    @State private var showLocationPicker = false
    @State private var date = Date()
    @State private var partySize = 2
    @State private var confirmationNumber = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Restaurant") {
                    Button {
                        showLocationPicker = true
                    } label: {
                        HStack {
                            Text(restaurantName.isEmpty ? "Choose restaurant…" : restaurantName)
                                .foregroundStyle(restaurantName.isEmpty ? Color.secondary : Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    if !restaurantPark.isEmpty {
                        Text(restaurantPark).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Details") {
                    DatePicker("Date & Time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Stepper("Party of \(partySize)", value: $partySize, in: 1...20)
                }

                Section("Confirmation") {
                    TextField("Confirmation #", text: $confirmationNumber)
                        .keyboardType(.asciiCapable)
                }

                Section("Notes") {
                    TextField("Special requests, notes…", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle("Add Reservation")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(
                    resort: resort,
                    category: "Food",
                    selectedPark: $restaurantPark,
                    selectedLocation: $restaurantName,
                    isAPEligible: $isAPEligible
                )
                .presentationDetents([.large])
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let res = DiningReservation(
            restaurantName: restaurantName.trimmingCharacters(in: .whitespaces),
            resort: resort,
            date: date,
            partySize: partySize,
            confirmationNumber: confirmationNumber.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        context.insert(res)
        try? context.save()
        dismiss()
    }
}

// MARK: - Dining Row (unchanged)

private struct DiningRow: View {
    let restaurant: BucketRestaurant

    var body: some View {
        HStack(spacing: 12) {
            if let avg = restaurant.averageRating {
                ZStack {
                    Circle()
                        .fill(ratingColor(avg).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text(String(format: "%.1f", avg))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ratingColor(avg))
                }
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(restaurant.name)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(restaurant.park)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(restaurant.category)
                        .font(.caption)
                        .foregroundStyle(categoryColor(restaurant.category))
                }
                if let avg = restaurant.averageRating {
                    StarDisplayView(rating: avg)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func ratingColor(_ r: Double) -> Color {
        if r >= 4.5 { return .green }
        if r >= 3.0 { return .orange }
        return .red
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Character Dining": return .blue
        case "Table Service":    return .green
        default:                 return .gray
        }
    }
}

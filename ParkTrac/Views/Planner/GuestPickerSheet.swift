import SwiftUI
import SwiftData

struct GuestPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Guest.name) private var allGuests: [Guest]
    @Environment(\.modelContext) private var context
    @State private var showAddForm = false
    @State private var newName = ""
    @State private var newHasDisney = false
    @State private var newHasUniversal = false
    @State private var newIsFrequent = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !allGuests.isEmpty {
                        Text("Quick Add").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(allGuests.filter(\.isFrequent)) { guest in
                                    guestChip(guest)
                                }
                            }
                            .padding(.horizontal)
                        }
                        if !allGuests.filter({ !$0.isFrequent }).isEmpty {
                            Text("All Guests").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal)
                            ForEach(allGuests.filter { !$0.isFrequent }) { guest in
                                guestRow(guest)
                            }
                        }
                    }

                    if showAddForm {
                        addGuestForm
                    } else {
                        Button { showAddForm = true } label: {
                            Label("Add Guest", systemImage: "plus.circle")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Who's Coming?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func isSelected(_ guest: Guest) -> Bool {
        appState.todayGuestIds.contains(guest.persistentModelID.hashValue.description)
    }
    private func toggle(_ guest: Guest) {
        let key = guest.persistentModelID.hashValue.description
        if appState.todayGuestIds.contains(key) {
            appState.todayGuestIds.removeAll { $0 == key }
        } else {
            appState.todayGuestIds.append(key)
        }
    }

    private func guestChip(_ guest: Guest) -> some View {
        let selected = isSelected(guest)
        return Button { toggle(guest) } label: {
            VStack(spacing: 4) {
                Text(guest.name).font(.caption.weight(.semibold))
                if !guest.hasDisneyPass && !guest.hasUniversalPass {
                    Text("~$109").font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(selected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func guestRow(_ guest: Guest) -> some View {
        let selected = isSelected(guest)
        return HStack {
            Button { toggle(guest) } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            Text(guest.name).font(.subheadline)
            if !guest.hasDisneyPass && !guest.hasUniversalPass {
                Text("~$109").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var addGuestForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Guest").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
            Toggle("Has Disney Pass", isOn: $newHasDisney)
            Toggle("Has Universal Pass", isOn: $newHasUniversal)
            Toggle("Frequent Guest", isOn: $newIsFrequent)
            HStack {
                Button("Cancel") { showAddForm = false }.foregroundStyle(.secondary)
                Spacer()
                Button("Add") {
                    guard !newName.isEmpty else { return }
                    let g = Guest(name: newName, hasDisneyPass: newHasDisney, hasUniversalPass: newHasUniversal, disneyPassTier: "", universalPassTier: "", isFrequent: newIsFrequent)
                    context.insert(g)
                    newName = ""; newHasDisney = false; newHasUniversal = false; newIsFrequent = true
                    showAddForm = false
                }
                .disabled(newName.isEmpty)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

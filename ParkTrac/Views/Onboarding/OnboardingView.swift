import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var names: [String] = ["", ""]
    @State private var focusedIndex: Int? = nil

    private var validNames: [String] { names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var canContinue: Bool { validNames.count >= 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(appState.selectedResort.theme.primaryColor)

                        Text("Who's in your party?")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)

                        Text("Add everyone's name so you can each rate rides and restaurants separately.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)

                    // Name fields
                    VStack(spacing: 12) {
                        ForEach(names.indices, id: \.self) { i in
                            HStack(spacing: 10) {
                                Image(systemName: "person.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(appState.selectedResort.theme.primaryColor.opacity(0.7))

                                TextField("Name", text: $names[i])
                                    .textContentType(.name)
                                    .submitLabel(i == names.count - 1 ? .done : .next)

                                if names.count > 1 {
                                    Button {
                                        names.remove(at: i)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            names.append("")
                        } label: {
                            Label("Add Another Person", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(appState.selectedResort.theme.primaryColor)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal)

                    // Continue button
                    Button {
                        finish()
                    } label: {
                        Text("Start Exploring")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(appState.selectedResort.theme.primaryColor, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.5)

                    Text("You can edit party members anytime in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") { finish() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func finish() {
        appState.partyMembers = validNames.isEmpty ? ["Me"] : validNames
        appState.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Edit Party Sheet (reused from Settings)

struct EditPartyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var names: [String] = []

    private var validNames: [String] { names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(names.indices, id: \.self) { i in
                        HStack {
                            TextField("Name", text: $names[i])
                                .textContentType(.name)
                            if names.count > 1 {
                                Button {
                                    names.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        names.append("")
                    } label: {
                        Label("Add Person", systemImage: "plus")
                    }
                } header: {
                    Text("Party Members")
                } footer: {
                    Text("Names appear on restaurant and hotel rating screens.")
                }
            }
            .navigationTitle("Edit Party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = validNames
                        appState.partyMembers = saved.isEmpty ? ["Me"] : saved
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                names = appState.partyMembers.isEmpty ? [""] : appState.partyMembers
            }
        }
    }
}

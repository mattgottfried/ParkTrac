import SwiftUI

struct JoinHouseholdSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let service = HouseholdSyncService.shared

    @State private var codeInput = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Join with a Code").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        TextField("e.g. SUNSET42", text: $codeInput)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.title3, design: .monospaced))
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)

                    Button {
                        join()
                    } label: {
                        Label("Join Household", systemImage: "person.badge.key.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
                    .padding(.horizontal)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    HStack {
                        Rectangle().fill(Color(.separator)).frame(height: 1)
                        Text("or").font(.caption).foregroundStyle(.secondary)
                        Rectangle().fill(Color(.separator)).frame(height: 1)
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Starting Fresh").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        Text("No code yet? Create a new household and share the code with your partner.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal)

                    Button {
                        create()
                    } label: {
                        Label("Create New Household", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Color.primary)
                    }
                    .disabled(isBusy)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    if isBusy {
                        ProgressView()
                    }
                }
                .padding(.top, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Household Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func join() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await service.join(code: codeInput)
                isBusy = false
                dismiss()
            } catch {
                isBusy = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func create() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                _ = try await service.create()
                isBusy = false
                dismiss()
            } catch {
                isBusy = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

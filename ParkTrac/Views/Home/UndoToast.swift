import SwiftUI
import SwiftData

// MARK: - Undo Delete Center

/// Deferred ("soft") delete with an Undo window.
///
/// Rows are hidden immediately and the real `context.delete` runs only after the
/// toast times out, so Undo just un-hides — no field snapshots, works for any model.
/// (SwiftData's own UndoManager isn't used because background telemetry inserts on the
/// main context would land in the same undo stack.)
/// Only touched from views and main-actor tasks.
@Observable
final class UndoDeleteCenter {
    static let shared = UndoDeleteCenter()

    /// Pending *and* already-committed deletions. Committed IDs stay hidden for the session
    /// so views holding a snapshot of models (e.g. a visit's entries) never touch a deleted one.
    private(set) var hiddenIds: Set<PersistentIdentifier> = []
    private(set) var message: String?

    private var pendingIds: Set<PersistentIdentifier> = []
    private var commitAction: (() -> Void)?
    private var timeoutTask: Task<Void, Never>?

    private init() {}

    func isHidden(_ model: some PersistentModel) -> Bool {
        hiddenIds.contains(model.persistentModelID)
    }

    /// Hides `models` now and deletes them after a short Undo window.
    func delete<T: PersistentModel>(
        _ models: [T],
        message: String,
        in context: ModelContext,
        afterCommit: (() -> Void)? = nil
    ) {
        commit()  // finalize any previous pending delete first
        guard !models.isEmpty else { return }

        let ids = Set(models.map(\.persistentModelID))
        pendingIds = ids
        hiddenIds.formUnion(ids)
        self.message = message
        commitAction = {
            for model in models { context.delete(model) }
            try? context.save()
            afterCommit?()
        }
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    func undo() {
        timeoutTask?.cancel()
        commitAction = nil
        hiddenIds.subtract(pendingIds)
        pendingIds = []
        withAnimation { message = nil }
    }

    /// Runs the pending delete now (timeout, a new delete, or the app backgrounding).
    func commit() {
        timeoutTask?.cancel()
        timeoutTask = nil
        let action = commitAction
        commitAction = nil
        pendingIds = []
        withAnimation { message = nil }
        action?()
    }
}

// MARK: - Undo Toast

struct UndoToast: View {
    private var center: UndoDeleteCenter { .shared }

    var body: some View {
        if let message = center.message {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { center.undo() }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sensoryFeedback(.impact(weight: .light), trigger: message)
        }
    }
}

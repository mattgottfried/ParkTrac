import Foundation
import CryptoKit

/// Device-local bookkeeping for the household sync engine: per-row content fingerprints
/// (used to detect local creates/updates/deletes without touching model call sites) and
/// per-type download watermarks (used for incremental CKQuery downloads).
///
/// Persisted as one JSON blob in UserDefaults, matching this app's existing convention for
/// device-local sync bookkeeping (see `rideCatalog_<parkId>`, `lastStatus_<rideId>`).
struct HouseholdSyncIndex: Codable {
    private static let defaultsKey = "householdSyncIndex_v1"

    private var fingerprints: [String: [String: String]] = [:]     // [typeName: [uuidString: fingerprint]]
    private var downloadWatermarks: [String: Date] = [:]           // [typeName: watermark]

    static func load() -> HouseholdSyncIndex {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let index = try? JSONDecoder().decode(HouseholdSyncIndex.self, from: data)
        else { return HouseholdSyncIndex() }
        return index
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Fingerprints (create/update/delete detection)

    func fingerprint(typeName: String, id: UUID) -> String? {
        fingerprints[typeName]?[id.uuidString]
    }

    mutating func setFingerprint(_ fingerprint: String, typeName: String, id: UUID) {
        fingerprints[typeName, default: [:]][id.uuidString] = fingerprint
    }

    mutating func removeFingerprint(typeName: String, id: UUID) {
        fingerprints[typeName]?.removeValue(forKey: id.uuidString)
    }

    /// UUIDs seen for this type as of the last scan — a fresh fetch missing one of these
    /// means that row was deleted locally since the last reconciliation pass.
    func knownIds(typeName: String) -> Set<UUID> {
        guard let entries = fingerprints[typeName] else { return [] }
        return Set(entries.keys.compactMap(UUID.init))
    }

    // MARK: - Download watermarks (incremental CKQuery)

    func downloadWatermark(typeName: String) -> Date {
        downloadWatermarks[typeName] ?? .distantPast
    }

    mutating func advanceDownloadWatermark(_ date: Date, typeName: String) {
        if date > downloadWatermark(typeName: typeName) {
            downloadWatermarks[typeName] = date
        }
    }
}

/// Computes a stable content fingerprint for a syncable row's domain fields (excludes
/// `id`/`syncUpdatedAt`, which shouldn't themselves affect whether a row is "changed").
enum HouseholdFingerprint {
    /// Unit separator — practically never appears in user-entered text, so plain
    /// concatenation can't collide the way naive comma/pipe joining could.
    private static let separator = "\u{1F}"

    static func compute(_ components: [String]) -> String {
        let joined = components.joined(separator: separator)
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

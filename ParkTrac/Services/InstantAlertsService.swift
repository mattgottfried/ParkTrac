import Foundation
import SwiftData
import UIKit
import UserNotifications

// MARK: - Reopen watch

/// "Tell me when this ride is back up." One-shot, today only, per device (UserDefaults).
struct ReopenWatch: Codable, Identifiable, Equatable {
    var id = UUID()
    var rideId: String
    var rideName: String
    var parkId: String
    var parkName: String
    var resortRaw: String
    /// Start of the day this watch applies to
    var day: Date

    var resort: ParkGroup { ParkGroup(rawValue: resortRaw) ?? .disney }
    var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// Pure rule (unit tested): fire once the ride is operating again.
    static func shouldFire(ride: DisplayRide?) -> Bool { ride?.isOperating == true }
}

@Observable
final class ReopenWatchService {
    static let shared = ReopenWatchService()
    private static let storageKey = "reopenWatches"

    private(set) var watches: [ReopenWatch] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([ReopenWatch].self, from: data) {
            watches = saved.filter(\.isToday)
        }
    }

    func watch(for rideId: String) -> ReopenWatch? {
        watches.first { $0.rideId == rideId && $0.isToday }
    }

    func add(ride: DisplayRide, parkName: String, resort: ParkGroup) {
        watches.removeAll { $0.rideId == ride.id }
        watches.append(ReopenWatch(rideId: ride.id, rideName: ride.name, parkId: ride.parkId,
                                   parkName: parkName, resortRaw: resort.rawValue,
                                   day: Calendar.current.startOfDay(for: .now)))
        persist()
        Task { @MainActor in
            await NotificationService.shared.requestAuthorization()
            InstantAlertsService.shared.watchesChanged()
        }
    }

    func remove(rideId: String) {
        watches.removeAll { $0.rideId == rideId }
        persist()
        Task { @MainActor in InstantAlertsService.shared.watchesChanged() }
    }

    func remove(id: UUID) {
        watches.removeAll { $0.id == id }
        persist()
    }

    /// After every live-data refresh. Skips watches the alert server is covering (it pushes instead).
    @MainActor
    func check(rides: [DisplayRide]) {
        let before = watches
        watches = watches.filter(\.isToday)
        let byId = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for watch in watches where ReopenWatch.shouldFire(ride: byId[watch.rideId]) {
            guard !InstantAlertsService.shared.covers(watch.id.uuidString) else { continue }
            NotificationService.shared.fireRideReopened(watch: watch, wait: byId[watch.rideId]?.waitMinutes)
            watches.removeAll { $0.id == watch.id }
        }
        if before != watches { persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(watches) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Server watch payload

/// One watch as the alert server (server/logic.ts) expects it. Field names must match.
struct ServerWatch: Codable, Equatable {
    enum Kind: String, Codable { case ll, wait, reopen }

    var id: String
    var kind: Kind
    var rideId: String
    var rideName: String
    var parkId: String
    var parkName: String
    var resort: String
    /// Epoch seconds
    var expiresAt: Double
    // ll
    var passLabel: String?
    var bookingAppName: String?
    var windowStart: Double?
    var windowEnd: Double?
    // wait
    var threshold: Int?
    var accessPass: String?
}

/// What the app knows about a wait alert (a plain copy of `RideAlert`, so building the payload is pure).
struct WaitAlertSnapshot {
    var id: String
    var rideId: String
    var rideName: String
    var parkId: String?
    var parkName: String?
    var resort: ParkGroup?
    var threshold: Int
}

extension RideAlert {
    /// Stable id shared with the server. Changing the threshold creates a new alert (new createdAt).
    var serverId: String { "alert-\(rideId)-\(Int(createdAt.timeIntervalSince1970))" }

    var snapshot: WaitAlertSnapshot {
        WaitAlertSnapshot(id: serverId, rideId: rideId, rideName: rideName, parkId: parkId,
                          parkName: parkName, resort: resortRaw.flatMap(ParkGroup.init(rawValue:)),
                          threshold: thresholdMinutes)
    }
}

enum InstantAlertsPayload {
    /// Wait alerts don't expire on their own; the server keeps them for a day past each sync.
    static let waitAlertLifetime: TimeInterval = 24 * 3600

    static func watches(ll: [LightningLaneWatch], alerts: [WaitAlertSnapshot], reopen: [ReopenWatch],
                        accessPass: (ParkGroup) -> AccessPass?, now: Date = .now,
                        calendar: Calendar = .current) -> [ServerWatch] {
        var out: [ServerWatch] = []
        for w in ll where w.windowEnd > now {
            out.append(ServerWatch(
                id: w.id.uuidString, kind: .ll, rideId: w.rideId, rideName: w.rideName, parkId: w.parkId,
                parkName: w.parkName ?? "", resort: w.resort.rawValue,
                expiresAt: w.windowEnd.timeIntervalSince1970,
                passLabel: w.passName ?? "Lightning Lane", bookingAppName: BookingApp.for(w.resort).appName,
                windowStart: w.windowStart.timeIntervalSince1970, windowEnd: w.windowEnd.timeIntervalSince1970))
        }
        for a in alerts {
            // Alerts made before parkId was stored can't be watched remotely — the app still checks them
            guard let parkId = a.parkId, !parkId.isEmpty else { continue }
            let resort = a.resort ?? .disney
            out.append(ServerWatch(
                id: a.id, kind: .wait, rideId: a.rideId, rideName: a.rideName, parkId: parkId,
                parkName: a.parkName ?? "", resort: resort.rawValue,
                expiresAt: now.addingTimeInterval(waitAlertLifetime).timeIntervalSince1970,
                threshold: a.threshold, accessPass: accessPass(resort)?.label))
        }
        for r in reopen where r.isToday {
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: r.day)) ?? now
            out.append(ServerWatch(
                id: r.id.uuidString, kind: .reopen, rideId: r.rideId, rideName: r.rideName, parkId: r.parkId,
                parkName: r.parkName, resort: r.resortRaw, expiresAt: endOfDay.timeIntervalSince1970))
        }
        return out
    }
}

// MARK: - Sync API

struct InstantAlertsSyncRequest: Encodable {
    var deviceId: String
    var token: String
    var environment: String
    var timeZone: String
    var watches: [ServerWatch]
}

struct InstantAlertsSyncResponse: Decodable {
    struct State: Decodable, Equatable {
        var lastNotifiedStart: Double?
        var fired: Bool?
    }
    var ok: Bool?
    var error: String?
    var watching: Int?
    var states: [String: State]?
    var lastError: String?
    var lastPushAt: Double?
}

// MARK: - Service

/// Instant alerts: a small server (server/, Deno Deploy) checks live data every minute and sends
/// Apple push notifications, so alerts don't wait for iOS's ≈hourly background refresh.
///
/// The app stays the source of truth: it uploads this phone's watches (Lightning Lane watches,
/// wait alerts, reopen watches) and applies what the server fired. While the server covers a
/// watch, the app's own checks skip it so you don't get two alerts.
@MainActor
@Observable
final class InstantAlertsService {
    static let shared = InstantAlertsService()

    static let defaultServerURL = "https://thrilltrack-alerts.mattgottfried.deno.net"
    /// Server-side coverage counts only if we synced this recently
    static let coverageWindow: TimeInterval = 3 * 3600

    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "instantAlertsEnabled")
            if isEnabled { start() } else { stop() }
        }
    }

    var serverURL: String {
        didSet { defaults.set(serverURL, forKey: "instantAlertsServerURL") }
    }

    private(set) var deviceToken: String?
    /// Persisted with `syncedIds` so a background launch still knows what the server covers
    private(set) var lastSync: Date? {
        didSet { defaults.set(lastSync, forKey: "instantAlertsLastSync") }
    }
    private(set) var syncError: String?
    /// Delivery problem reported by the server (e.g. Apple rejected the token)
    private(set) var serverError: String? {
        didSet { defaults.set(serverError, forKey: "instantAlertsServerError") }
    }
    private(set) var watchingCount = 0
    private(set) var lastPushAt: Date?
    private(set) var isSyncing = false
    /// Watch ids included in the last successful sync
    private var syncedIds: Set<String> = [] {
        didSet { defaults.set(Array(syncedIds), forKey: "instantAlertsSyncedIds") }
    }
    private var pendingSync: Task<Void, Never>?

    /// Random per-install id; the server stores watches under it.
    let deviceId: String

    private init() {
        isEnabled = defaults.bool(forKey: "instantAlertsEnabled")
        serverURL = defaults.string(forKey: "instantAlertsServerURL") ?? Self.defaultServerURL
        deviceToken = defaults.string(forKey: "apnsDeviceToken")
        lastSync = defaults.object(forKey: "instantAlertsLastSync") as? Date
        serverError = defaults.string(forKey: "instantAlertsServerError")
        syncedIds = Set(defaults.stringArray(forKey: "instantAlertsSyncedIds") ?? [])
        if let id = defaults.string(forKey: "instantAlertsDeviceId") {
            deviceId = id
        } else {
            deviceId = UUID().uuidString
            defaults.set(deviceId, forKey: "instantAlertsDeviceId")
        }
    }

    static var environment: String {
        #if DEBUG
        return "sandbox"      // Xcode builds use the development push environment
        #else
        return "production"   // TestFlight / App Store
        #endif
    }

    // MARK: Coverage

    /// True when the server has this watch and can push for it — local checks skip it.
    func covers(_ watchId: String) -> Bool {
        guard isEnabled, deviceToken != nil, serverError == nil,
              let lastSync, Date.now.timeIntervalSince(lastSync) < Self.coverageWindow else { return false }
        return syncedIds.contains(watchId)
    }

    // MARK: Lifecycle

    /// App became active: re-register (tokens can change) and sync.
    func appBecameActive() {
        guard isEnabled else { return }
        UIApplication.shared.registerForRemoteNotifications()
        watchesChanged()
    }

    private func start() {
        Task {
            await NotificationService.shared.requestAuthorization()
            UIApplication.shared.registerForRemoteNotifications()
            watchesChanged()
        }
    }

    private func stop() {
        syncedIds = []
        lastSync = nil
        let body = ["deviceId": deviceId]
        guard let url = endpoint("v1/unregister") else { return }
        Task.detached {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func didRegister(token: String) {
        let changed = token != deviceToken
        deviceToken = token
        defaults.set(token, forKey: "apnsDeviceToken")
        if changed { serverError = nil }
        watchesChanged()
    }

    func registrationFailed(_ message: String) {
        syncError = "Couldn't register for push notifications: \(message)"
    }

    /// Something a watch depends on changed — sync soon (coalesces bursts).
    func watchesChanged() {
        guard isEnabled else { return }
        pendingSync?.cancel()
        pendingSync = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    /// After a foreground refresh: keep the server's copy fresh without syncing every minute.
    func refreshIfStale() {
        guard isEnabled else { return }
        if lastSync.map({ Date.now.timeIntervalSince($0) > 10 * 60 }) ?? true { watchesChanged() }
    }

    // MARK: Sync

    func sync() async {
        guard isEnabled, let token = deviceToken, let url = endpoint("v1/sync"), !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let context = PersistenceController.container.mainContext
        let alerts = ((try? context.fetch(FetchDescriptor<RideAlert>())) ?? []).filter(\.isActive)
        let watches = InstantAlertsPayload.watches(
            ll: LightningLaneWatchService.shared.watches.filter(\.isToday),
            alerts: alerts.map(\.snapshot),
            reopen: ReopenWatchService.shared.watches,
            accessPass: AccessPass.held(at:))
        let body = InstantAlertsSyncRequest(deviceId: deviceId, token: token, environment: Self.environment,
                                            timeZone: TimeZone.current.identifier, watches: watches)

        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let decoded = try? JSONDecoder().decode(InstantAlertsSyncResponse.self, from: data)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let decoded else {
                syncError = decoded?.error ?? "Server error (\((response as? HTTPURLResponse)?.statusCode ?? 0))"
                return
            }
            syncError = nil
            serverError = decoded.lastError
            watchingCount = decoded.watching ?? watches.count
            lastPushAt = decoded.lastPushAt.map(Date.init(timeIntervalSince1970:))
            lastSync = .now
            syncedIds = Set(watches.map(\.id))
            apply(states: decoded.states ?? [:], alerts: alerts, context: context)
        } catch {
            syncError = "Can't reach the alert server — using on-phone checks. (\(error.localizedDescription))"
        }
    }

    /// Mirror what the server already alerted about, so the app doesn't alert again.
    private func apply(states: [String: InstantAlertsSyncResponse.State], alerts: [RideAlert], context: ModelContext) {
        guard !states.isEmpty else { return }
        for watch in LightningLaneWatchService.shared.watches {
            if let start = states[watch.id.uuidString]?.lastNotifiedStart {
                LightningLaneWatchService.shared.markNotified(id: watch.id, returnStart: Date(timeIntervalSince1970: start))
            }
        }
        var changed = false
        for alert in alerts where states[alert.serverId]?.fired == true {
            alert.isActive = false
            changed = true
        }
        if changed { try? context.save() }
        for watch in ReopenWatchService.shared.watches where states[watch.id.uuidString]?.fired == true {
            ReopenWatchService.shared.remove(id: watch.id)
        }
    }

    private func endpoint(_ path: String) -> URL? {
        let base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url.appending(path: path)
    }

    /// For Settings: "Watching 3 · synced 2 min ago"
    var statusText: String {
        if let serverError { return serverError }
        if let syncError { return syncError }
        if deviceToken == nil { return "Waiting for push registration…" }
        guard let lastSync else { return "Not synced yet" }
        let ago = lastSync.formatted(.relative(presentation: .named))
        return watchingCount == 1 ? "Watching 1 alert · synced \(ago)" : "Watching \(watchingCount) alerts · synced \(ago)"
    }

    var isHealthy: Bool {
        serverError == nil && syncError == nil && deviceToken != nil && lastSync != nil
    }
}

// MARK: - App delegate (push token, quick actions)

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Hooks up Home Screen quick actions (cold launch here, warm via QuickActionSceneDelegate)
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { QuickActions.handle(item) }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in InstantAlertsService.shared.didRegister(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in InstantAlertsService.shared.registrationFailed(message) }
    }
}

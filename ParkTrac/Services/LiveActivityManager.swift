import Foundation
import ActivityKit
import SwiftData

/// Starts and ends Live Activities for return-time passes (Lightning Lane /
/// Express Now / DAS / AAP), the wait stopwatch, dining reservation
/// countdowns, rope-drop (park opening) countdowns, and next-booking
/// eligibility countdowns. Main-app only — the widget extension only renders
/// the ContentState this hands to ActivityKit.
///
/// Simplification: one active activity per mode. Starting a new one replaces
/// whichever was running for that mode; there's no per-item correlation, so
/// starting a second concurrent activity of the same mode ends the first.
/// Fine for the common case of one active pass/timer/countdown at a time.
/// Different modes coexist (ActivityKit supports multiple concurrent
/// activities), e.g. a return-time countdown alongside a next-booking one.
///
/// Not @MainActor: called from AppState (not itself MainActor-isolated) as
/// well as directly from view actions. Every call site in this app runs on
/// the main thread in practice (SwiftUI button actions, AppState mutations).
enum LiveActivityManager {
    private static var returnTimeActivity: Activity<ThrillTrackActivityAttributes>?
    private static var waitTimerActivity: Activity<ThrillTrackActivityAttributes>?
    private static var diningActivity: Activity<ThrillTrackActivityAttributes>?
    private static var ropeDropActivity: Activity<ThrillTrackActivityAttributes>?
    private static var nextBookingActivity: Activity<ThrillTrackActivityAttributes>?

    // MARK: - Return time (Lightning Lane / Express Now / DAS / AAP)

    static func startReturnTime(passLabel: String, rideName: String, parkName: String, returnEnd: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endReturnTime()
        let attributes = ThrillTrackActivityAttributes(
            mode: .returnTime, label: passLabel, title: rideName, subtitle: parkName
        )
        let state = ThrillTrackActivityAttributes.ContentState(countdownEnd: returnEnd, startedAt: nil, postedMinutes: nil)
        let content = ActivityContent(state: state, staleDate: returnEnd)
        returnTimeActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endReturnTime() {
        guard let activity = returnTimeActivity else { return }
        returnTimeActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Wait stopwatch

    static func startWaitTimer(rideName: String, parkName: String, startedAt: Date, postedMinutes: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endWaitTimer()
        let attributes = ThrillTrackActivityAttributes(
            mode: .waitTimer, label: "Wait Timer", title: rideName, subtitle: parkName
        )
        let state = ThrillTrackActivityAttributes.ContentState(countdownEnd: nil, startedAt: startedAt, postedMinutes: postedMinutes)
        let content = ActivityContent(state: state, staleDate: nil)
        waitTimerActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endWaitTimer() {
        guard let activity = waitTimerActivity else { return }
        waitTimerActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Dining reservation countdown

    static func startDining(restaurantName: String, parkName: String, partySize: Int, reservationTime: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endDining()
        let subtitle = partySize > 0 ? "Party of \(partySize) · \(parkName)" : parkName
        let attributes = ThrillTrackActivityAttributes(
            mode: .dining, label: "Dining Reservation", title: restaurantName, subtitle: subtitle
        )
        let state = ThrillTrackActivityAttributes.ContentState(countdownEnd: reservationTime, startedAt: nil, postedMinutes: nil)
        let content = ActivityContent(state: state, staleDate: reservationTime)
        diningActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endDining() {
        guard let activity = diningActivity else { return }
        diningActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// The reservation this manager is currently counting down to (nil if none).
    /// Lets scene-active sync avoid restarting the activity every foreground.
    static var diningReservationTime: Date? {
        diningActivity?.content.state.countdownEnd
    }

    // MARK: - Rope drop (park opening) countdown

    static func startRopeDrop(parkName: String, openingTime: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endRopeDrop()
        let attributes = ThrillTrackActivityAttributes(
            mode: .ropeDrop, label: "Rope Drop", title: parkName, subtitle: ""
        )
        let state = ThrillTrackActivityAttributes.ContentState(countdownEnd: openingTime, startedAt: nil, postedMinutes: nil)
        let content = ActivityContent(state: state, staleDate: openingTime)
        ropeDropActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endRopeDrop() {
        guard let activity = ropeDropActivity else { return }
        ropeDropActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Next Lightning Lane booking eligibility countdown

    static func startNextBooking(rideName: String, eligibleAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endNextBooking()
        let attributes = ThrillTrackActivityAttributes(
            mode: .nextBooking, label: "Next Booking", title: rideName, subtitle: "Estimate — verify in official app"
        )
        let state = ThrillTrackActivityAttributes.ContentState(countdownEnd: eligibleAt, startedAt: nil, postedMinutes: nil)
        let content = ActivityContent(state: state, staleDate: eligibleAt)
        nextBookingActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endNextBooking() {
        guard let activity = nextBookingActivity else { return }
        nextBookingActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Dining activity sync

    /// Starts/updates/ends the dining Live Activity for the soonest upcoming
    /// reservation that is still later today. Idempotent — safe to call on
    /// every foreground and after any create/delete; it no-ops when the
    /// countdown target hasn't changed, so it won't thrash the activity.
    ///
    /// Call sites: scene becomes active (covers email-scraped reservations
    /// created without a view), reservation saved, reservation deleted.
    static func syncDiningActivity(context: ModelContext) {
        let now = Date()
        let calendar = Calendar.current
        let descriptor = FetchDescriptor<DiningReservation>(sortBy: [SortDescriptor(\.date)])
        guard let reservations = try? context.fetch(descriptor) else { return }
        let soonest = reservations.first { res in
            !res.isCompleted && res.date > now && calendar.isDateInToday(res.date)
        }
        guard let res = soonest else {
            endDining()
            return
        }
        // Restart-thrash guard: only (re)start when the target reservation changed.
        if diningReservationTime == res.date { return }
        startDining(
            restaurantName: res.restaurantName,
            parkName: res.resort,
            partySize: res.partySize,
            reservationTime: res.date
        )
    }
}

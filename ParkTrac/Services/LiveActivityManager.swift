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
    private static var parkDayActivity: Activity<ThrillTrackActivityAttributes>?

    // MARK: - Return time (Lightning Lane / Express Now / DAS / AAP)

    /// - Parameter returnStart: when a timed window opens (progress bar); nil for DAS/AAP
    static func startReturnTime(passLabel: String, rideName: String, parkName: String, returnEnd: Date?,
                                returnStart: Date? = nil, rideId: String? = nil, resortRaw: String? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endReturnTime()
        let attributes = ThrillTrackActivityAttributes(
            mode: .returnTime, label: passLabel, title: rideName, subtitle: parkName,
            rideId: rideId, resortRaw: resortRaw
        )
        let state = ThrillTrackActivityAttributes.ContentState(countdownEnd: returnEnd, startedAt: nil, postedMinutes: nil,
                                                               windowStart: returnStart)
        let content = ActivityContent(state: state, staleDate: returnEnd)
        returnTimeActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endReturnTime() {
        returnTimeActivity = nil
        endAll(.returnTime)
    }

    // MARK: - Wait stopwatch

    static func startWaitTimer(rideName: String, parkName: String, startedAt: Date, postedMinutes: Int,
                               rideId: String? = nil, resortRaw: String? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endWaitTimer()
        let attributes = ThrillTrackActivityAttributes(
            mode: .waitTimer, label: "Wait Timer", title: rideName, subtitle: parkName,
            rideId: rideId, resortRaw: resortRaw
        )
        let state = ThrillTrackActivityAttributes.ContentState(countdownEnd: nil, startedAt: startedAt, postedMinutes: postedMinutes)
        let content = ActivityContent(state: state, staleDate: nil)
        waitTimerActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endWaitTimer() {
        waitTimerActivity = nil
        endAll(.waitTimer)
    }

    /// Ends every running activity of a mode — including ones started before an app relaunch
    /// (e.g. when a Live Activity button launched the app in the background).
    private static func endAll(_ mode: ThrillTrackActivityAttributes.Mode) {
        for activity in Activity<ThrillTrackActivityAttributes>.activities where activity.attributes.mode == mode {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Dining reservation countdown

    static func startDining(restaurantName: String, parkName: String, partySize: Int, reservationTime: Date,
                            resortRaw: String? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endDining()
        let subtitle = partySize > 0 ? "Party of \(partySize) · \(parkName)" : parkName
        let attributes = ThrillTrackActivityAttributes(
            mode: .dining, label: "Dining Reservation", title: restaurantName, subtitle: subtitle,
            resortRaw: resortRaw
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

    static func startRopeDrop(parkName: String, openingTime: Date, resortRaw: String? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endRopeDrop()
        let attributes = ThrillTrackActivityAttributes(
            mode: .ropeDrop, label: "Rope Drop", title: parkName, subtitle: "", resortRaw: resortRaw
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

    static func startNextBooking(rideName: String, eligibleAt: Date, resortRaw: String? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endNextBooking()
        let attributes = ThrillTrackActivityAttributes(
            mode: .nextBooking, label: "Next Booking", title: rideName, subtitle: "Estimate — verify in official app",
            resortRaw: resortRaw
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

    // MARK: - Park Day (today's live plan)

    static let parkDayEnabledKey = "parkDayActivity"
    static var parkDayEnabled: Bool {
        UserDefaults.standard.object(forKey: parkDayEnabledKey) as? Bool ?? true
    }

    /// Starts, updates or (with nil) ends the Park Day activity. No-ops when nothing changed,
    /// so it's safe to call after every wait-time refresh.
    static func updateParkDay(title: String, resortRaw: String? = nil, state: ThrillTrackActivityAttributes.ContentState?) {
        guard parkDayEnabled, let state else {
            endParkDay()
            return
        }
        // Survives an app relaunch: pick the running one back up
        let existing = parkDayActivity
            ?? Activity<ThrillTrackActivityAttributes>.activities.first { $0.attributes.mode == .parkDay }
        let content = ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(30 * 60))
        if let existing, existing.attributes.title == title {
            parkDayActivity = existing
            guard existing.content.state != state else { return }
            Task { await existing.update(content) }
            return
        }
        endParkDay()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ThrillTrackActivityAttributes(mode: .parkDay, label: "Next Up", title: title, subtitle: "",
                                                       resortRaw: resortRaw)
        parkDayActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endParkDay() {
        let running = Activity<ThrillTrackActivityAttributes>.activities.filter { $0.attributes.mode == .parkDay }
        parkDayActivity = nil
        for activity in running {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
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
            reservationTime: res.date,
            resortRaw: res.resort
        )
    }
}

// MARK: - Park Day content (pure, unit tested)

enum ParkDayActivity {
    /// "Get in line ~2:16 PM · ~35 min wait · 6 min walk" for a ride, "At 6:30 PM" for a set-time stop.
    static func detail(for stop: PlannedStop, now: Date = .now) -> String {
        guard stop.kind == "ride" else { return "At \(time(stop.start))" }
        let arrive = stop.start.addingTimeInterval(Double(stop.walkMinutes) * 60)
        var parts = [arrive <= now.addingTimeInterval(120) ? "Go now" : "Get in line ~\(time(arrive))"]
        if stop.walkMinutes > 0 { parts.append("\(stop.walkMinutes) min walk") }
        return parts.joined(separator: " · ")
    }

    /// The Lock Screen / Dynamic Island content for the live plan, or nil when there's nothing next.
    /// Stops shown on the Lock Screen timeline
    static let timelineCount = 3

    static func state(stops: [PlannedStop], done: Int, total: Int, rain: String?,
                      now: Date = .now) -> ThrillTrackActivityAttributes.ContentState? {
        guard let stop = stops.first else { return nil }
        let then = stops.dropFirst().first.map { "Then: \($0.title) (\(time($0.start)))" }
        let upcoming = stops.prefix(timelineCount).map { s in
            ThrillTrackActivityAttributes.UpcomingStop(
                title: s.title,
                // Rides: when to get in line (after the walk); set-time events: their start
                time: s.kind == "ride" ? s.start.addingTimeInterval(Double(s.walkMinutes) * 60) : s.start,
                wait: s.kind == "ride" ? s.waitMinutes : nil,
                kind: s.kind)
        }
        return ThrillTrackActivityAttributes.ContentState(
            countdownEnd: nil, startedAt: nil, postedMinutes: nil,
            stopTitle: stop.title,
            stopWait: stop.kind == "ride" ? stop.waitMinutes : nil,
            stopDetail: detail(for: stop, now: now),
            thenText: then,
            progressText: total > 0 ? "\(done) of \(total) done" : nil,
            rainText: rain,
            stopRideId: stop.kind == "ride" ? stop.rideId : nil,
            upcoming: Array(upcoming))
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Live Activity buttons (app side)

/// Runs the Live Activity buttons (`LiveActivityIntents.swift`) inside the app. Registered in
/// `ParkTracApp.init`, so it works even when a button launches the app in the background.
@MainActor
enum LiveActivityActionHandler {
    static func register() {
        LiveActivityActions.handler = { action in await handle(action) }
    }

    static func handle(_ action: LiveActivityAction) async {
        switch action {
        case .done(let rideId):
            ItineraryService.shared.markDone(rideId)
            refreshParkDay()
        case .skip(let rideId):
            ItineraryService.shared.skip(rideId)
            refreshParkDay()
        case .finishTimer:
            finishTimer()
        case .usedReturn(let rideId):
            usedReturn(rideId: rideId)
        }
    }

    /// Push the plan's new next stop right away; the next foreground refresh re-plans fully.
    private static func refreshParkDay() {
        let service = ItineraryService.shared
        guard let plan = service.itinerary,
              let running = Activity<ThrillTrackActivityAttributes>.activities.first(where: { $0.attributes.mode == .parkDay })
        else { return }
        LiveActivityManager.updateParkDay(
            title: running.attributes.title, resortRaw: running.attributes.resortRaw,
            state: ParkDayActivity.state(stops: service.live?.stops ?? [], done: plan.doneIds.count,
                                         total: plan.rides.count,
                                         rain: RainForecastService.shared.headline(for: plan.resort)))
    }

    /// "I'm On": log the ride with the time waited, the same as the stopwatch's Done Waiting.
    private static func finishTimer() {
        let defaults = UserDefaults.standard
        let running = Activity<ThrillTrackActivityAttributes>.activities.first { $0.attributes.mode == .waitTimer }
        let startTs = defaults.double(forKey: "activeTimerStart")
        if let rideId = defaults.string(forKey: "activeTimerRideId"), startTs > 0 {
            let posted = defaults.integer(forKey: "timerPostedMinutes")
            let log = RideLog(
                rideId: rideId,
                rideName: running?.attributes.title ?? defaults.string(forKey: "timerRideName") ?? "",
                parkId: defaults.string(forKey: "timerResort") ?? "",   // the stopwatch stores the park id here
                parkName: running?.attributes.subtitle ?? "",
                resort: running?.attributes.resortRaw ?? "",
                riddenAt: .now,
                waitMinutes: posted == 0 ? nil : posted,
                actualWaitMinutes: TimerMath.actualMinutes(start: Date(timeIntervalSince1970: startTs)),
                notes: "",
                wasGoodTimeDeal: GoodTimeService.shared.deal(for: rideId) != nil)
            let context = PersistenceController.container.mainContext
            context.insert(log)
            try? context.save()
            RideMilestoneService.checkMilestones(rideId: log.rideId, rideName: log.rideName, resort: log.resort, context: context)
        }
        for key in ["activeTimerRideId", "activeTimerStart", "timerRideName", "timerPostedMinutes", "timerResort"] {
            defaults.removeObject(forKey: key)
        }
        LiveActivityManager.endWaitTimer()
        NotificationCenter.default.post(name: .waitTimerChangedExternally, object: nil)
    }

    /// "Used It": tick off today's return for this ride and end its countdown.
    private static func usedReturn(rideId: String) {
        let context = PersistenceController.container.mainContext
        let items = (try? context.fetch(FetchDescriptor<PlanItem>())) ?? []
        for item in items where TimerMath.isOpenReturn(item, rideId: rideId) {
            item.isDone = true
        }
        try? context.save()
        LiveActivityManager.endReturnTime()
    }
}

/// Small pure pieces of the button actions (unit tested).
enum TimerMath {
    /// Same rounding as the stopwatch: whole minutes, at least 1
    static func actualMinutes(start: Date, now: Date = .now) -> Int {
        max(1, Int(now.timeIntervalSince(start) / 60))
    }

    /// Today's unfinished Lightning Lane / DAS / AAP return for a ride
    static func isOpenReturn(_ item: PlanItem, rideId: String, calendar: Calendar = .current, now: Date = .now) -> Bool {
        (item.kind == "ll" || item.kind == "aap") && !item.isDone && item.rideId == rideId
            && calendar.isDate(item.date, inSameDayAs: now)
    }
}

extension Notification.Name {
    /// The stopwatch was stopped from outside the app's UI (a Live Activity button)
    static let waitTimerChangedExternally = Notification.Name("waitTimerChangedExternally")
}

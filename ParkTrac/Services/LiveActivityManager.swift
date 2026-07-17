import Foundation
import ActivityKit

/// Starts and ends Live Activities for return-time passes (Lightning Lane /
/// Express Now / DAS / AAP) and the wait stopwatch. Main-app only — the
/// widget extension only renders the ContentState this hands to ActivityKit.
///
/// Simplification: one active activity per mode. Starting a new one replaces
/// whichever was running; there's no per-PlanItem correlation, so marking a
/// second concurrent pass "Done" while a different one is still open will
/// end whichever activity is currently showing. Fine for the common case of
/// one active pass/timer at a time.
///
/// Not @MainActor: called from AppState (not itself MainActor-isolated) as
/// well as directly from view actions. Every call site in this app runs on
/// the main thread in practice (SwiftUI button actions, AppState mutations).
enum LiveActivityManager {
    private static var returnTimeActivity: Activity<ThrillTrackActivityAttributes>?
    private static var waitTimerActivity: Activity<ThrillTrackActivityAttributes>?

    static func startReturnTime(passLabel: String, rideName: String, parkName: String, returnEnd: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endReturnTime()
        let attributes = ThrillTrackActivityAttributes(
            mode: .returnTime, passLabel: passLabel, rideName: rideName, parkName: parkName
        )
        let state = ThrillTrackActivityAttributes.ContentState(returnEnd: returnEnd, startedAt: nil, postedMinutes: nil)
        let content = ActivityContent(state: state, staleDate: returnEnd)
        returnTimeActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endReturnTime() {
        guard let activity = returnTimeActivity else { return }
        returnTimeActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    static func startWaitTimer(rideName: String, parkName: String, startedAt: Date, postedMinutes: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endWaitTimer()
        let attributes = ThrillTrackActivityAttributes(
            mode: .waitTimer, passLabel: "Wait Timer", rideName: rideName, parkName: parkName
        )
        let state = ThrillTrackActivityAttributes.ContentState(returnEnd: nil, startedAt: startedAt, postedMinutes: postedMinutes)
        let content = ActivityContent(state: state, staleDate: nil)
        waitTimerActivity = try? Activity.request(attributes: attributes, content: content)
    }

    static func endWaitTimer() {
        guard let activity = waitTimerActivity else { return }
        waitTimerActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

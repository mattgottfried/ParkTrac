# ParkTrac — Feature Ideas

## Wait Time Stopwatch

Track actual time spent in line vs. the posted wait time for each ride.

**How it works:**
- In `RideDetailSheet`, add a "Start Timer" button when you join a queue
- Stopwatch runs in the foreground; persists across app backgrounding via a `startedAt: Date` stored in `AppState` (or UserDefaults)
- When you tap "I'm on!" (or a new "Done waiting" button), it stops and records the elapsed time alongside the posted wait at that moment
- Result saved to a new field on `RideLog` (e.g. `actualWaitMinutes: Int?`) or a lightweight `WaitAccuracyRecord` model

**What to show:**
- Live elapsed time on the ride card / detail sheet while timing is active
- After stopping: "Posted: 45 min · Actual: 38 min · Saved 7 min"
- In `StatsView`: aggregate accuracy stats — "Disney posted times are X% accurate based on your Y rides"
- Could feed into `WaitTimePredictionService` as a personal correction factor

**Implementation notes:**
- Only one ride can be timed at once — starting a new timer cancels the previous
- `AppState` holds `activeTimerRideId: String?` and `activeTimerStart: Date?`
- No SwiftData model needed for the timer state itself — just UserDefaults
- `WaitAccuracyRecord` (or a field on `RideLog`): `postedWait: Int`, `actualWait: Int`, `date: Date`, `rideId: String`

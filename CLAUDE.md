# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Naming note**: the app's Home Screen name (`CFBundleDisplayName` in Info.plist) is **ThrillTrack**. The Xcode project file, target, scheme, bundle identifier, module name, and folder are all still named `ParkTrac` — that's intentional (renaming those carries real risk to App Store Connect/TestFlight/CloudKit continuity and isn't required for the display name to read "ThrillTrack"). Don't "fix" the technical name to match unless explicitly asked.

## Build & Run

This is a native iOS/iPadOS app. There is no CLI build — use Xcode or `xcodebuild`:

```bash
# Build for simulator (no signing required)
xcodebuild -project ParkTrac.xcodeproj -scheme ParkTrac -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run on simulator
xcodebuild -project ParkTrac.xcodeproj -scheme ParkTrac -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath /tmp/ParkTracBuild build
```

```bash
# Unit tests (ParkTracTests target — pure logic only; UI is still verified in the simulator)
xcodebuild test -project ParkTrac.xcodeproj -scheme ParkTrac -destination 'platform=iOS Simulator,name=iPhone 16'
```

`ParkTracTests/` is a folder-synced group (like `TrillTrackWidget/`): new test files there are picked up automatically, no pbxproj edits. Tests cover the AAP/DAS return rules, themeparks.wiki Lightning Lane + schedule decoding, `LightningLaneWatchService.alertStart`, deep-link parsing, CSV/day-summary export, `WalkEstimate`, ride heights / name matching / `AreaEntry`, the instant-alerts payload, parking spots, Good Time to Ride, the Trip Planner, the Smart Planner engine / Siri pick, and the Genie-style live plan (order, interests, Tip Board), `MapFocus` and `LaunchResort`. Keep new business logic in pure/static functions so it can be tested here. Resort `rawValue`s are persisted in SwiftData (`PlanItem.resort`, `RideLog.resort`, …) — never rename existing `ParkGroup` cases/raw values.

**When adding new Swift source files**, the file MUST be registered in `ParkTrac.xcodeproj/project.pbxproj` in four places: `PBXBuildFile`, `PBXFileReference`, the owning `PBXGroup`'s `children`, and `PBXSourcesBuildPhase`. Missing this step causes "No such module" or linker errors at build time. When deleting files, remove all four entries. The project uses synthetic sequential IDs (`AA00…`) — take the next unused pair.

## Architecture

**Target**: iOS 17+, SwiftUI, `@Observable` macro (not `ObservableObject`), SwiftData for persistence.

### Resorts (`ParkDestination.swift`)

`ParkGroup` has four cases: `.disney` (Walt Disney World), `.universal` (Universal Orlando), `.tokyoDisney`, `.universalJapan`. Use `brand` (Disney vs Universal — icons, hotel tiers) or `isOrlando` (ticket prices, annual passes/blockouts, crowd calendar, seeded restaurants/hotels, DAS/AAP) rather than comparing to `.disney` / `.universal`. Each resort has `timeZone` (park-local hours — `ParkTime.formatter`, `WaitTimesViewModel.dayString`), `currencyCode`, and `returnPassNames` (Lightning Lane Multi/Single Pass in Orlando, Priority Pass / Premier Access at Tokyo). Orlando destination UUIDs are hardcoded; Japan's are resolved from `GET /destinations` by `apiSlug` and cached (`ParkAPIService.fetchParks(for:)` — always use it, not `fetchDestinationChildren` directly).

### Versions

`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` live only in the **project-level** build configs, so the app, widget extension and tests always match (App Store Connect flags an extension whose CFBundleVersion differs from the app's). Bump them there; don't add per-target overrides.

### TestFlight notes

Xcode Cloud reads `TestFlight/WhatToTest.en-US.txt` as the build's "What to Test". **Rewrite it with every push** that changes the app: what's new and what to check, in plain language (max 4,000 characters).

### Xcode Cloud & upload limits

Every push to `claude/vigilant-lamport-6DitA` triggers an Xcode Cloud archive + TestFlight upload, and App Store Connect caps uploads per app per day (ITMS-90382 "Upload limit reached" — wait a day). Xcode Cloud manages build numbers itself (uploads use its number, not `CURRENT_PROJECT_VERSION`).

- **Default: every merge gets `[ci skip]`** in the merge commit title/message — including app changes. The user builds only when there's an absolute need to test something on device, or when they explicitly ask. Batch features between builds.
- Keep `TestFlight/WhatToTest.en-US.txt` **cumulative since the last build**: each app change adds to it, so the next build's notes cover everything unbuilt.
- To build (user asked / testing truly needed): merge without `[ci skip]`, or have the user start the workflow in Xcode Cloud on the latest commit. Changes that need a new App ID capability (push, Time Sensitive, …) must wait until the user has enabled it in the developer portal.
- When merging via the GitHub API, pass `commit_title: "Merge pull request #N … [ci skip]"`.

### Five-Tab Structure (`ContentView.swift`)
1. **Wait Times** — `ParkMapView` — full-screen MapKit map with live ride wait time pins + a bottom panel listing rides/shows
2. **My Day** — `DayPlannerView` — today's plan (rides, dining, Lightning Lane windows, guests)
3. **Bucket List** — `BucketListView` — restaurants/hotels checklists with filters, sort, custom entries, and photos
4. **Stats** — `StatsView` — hub linking dining log (`MyDiningView`), ride counter, spending, crowd calendar, badges, etc.
5. **Settings** — `SettingsView` — prefs, resort switch, passes, tools, storage/sync status

A banner stack (resort switcher, blockout, return-time, wait-timer) sits above the TabView. On cold launch a `LaunchResortView` overlay (in `ContentView.swift`) asks for the resort while parks load underneath — it suggests the resort you're at (`LaunchResort.suggested`, last known location within 10 km) else the last one; skipped for deep links/notifications/Siri/quick actions and right after onboarding; Settings → "Choose Resort at Launch" (`askResortOnLaunch`, default on). The app has **no third-party dependencies** — no SPM packages (GoogleMobileAds was removed).

### Persistence (`PersistenceController.swift`)

One `ModelContainer` built from **two ModelConfigurations**:
- **User data** (unnamed config → existing `default.store`, CloudKit `.automatic`): `BucketRestaurant`, `HotelStay`, `RideLog`, `DiningReservation`, `RideAlert`, `PlanItem`, `PurchaseLog`, `Guest`, `WaitTimerLog`, `VisitSaving`
- **Telemetry** (named `"Telemetry"` config, local-only, no CloudKit): `WaitTimeRecord`, `DowntimeRecord`

The user config must stay **unnamed** — naming it changes the store URL and orphans existing user data. Container init falls back CloudKit → local-only → in-memory (`PersistenceController.storageMode`); never `try!`. `BackgroundRefreshService` opens the telemetry store via `PersistenceController.makeTelemetryContainer()` — same named config, same store file.

### Data Flow

**Live wait times**:
`ParkAPIService` (actor) → `WaitTimesViewModel` (@Observable) → `ParkMapView` + bottom panel

- Parks are discovered **dynamically** at launch: `ParkAPIService.fetchDestinationChildren(destinationId:)` returns park IDs — there are **no hardcoded park entity IDs**. Only the destination IDs in `ParkGroup` are hardcoded.
- `WaitTimesViewModel.loadAllParks()` fetches parks for both resorts concurrently. Rides auto-refresh every 60 seconds while the Wait Times tab is visible.
- The park filter follows the map (`MapFocus.decide` in `ParkMapView.swift`: span ≥ 0.05 → all parks, ≤ 0.035 near a park → that park, in between → keep); the top-left dropdown picks a park and flies there. The hours bar and park comparison show only when a single park is in focus. The bottom panel expands/collapses by dragging or tapping its whole header (grabber + park name line), following the finger (`PanelDrag`). Ride cards (`RideCardView`) lead with a colored wait tile, then name + Must-Do star, one subtitle line (good-time deal / down / closed) and one detail line (return pass, walk, thrill dot + height). `WaitTile` (in `RideCardView.swift`) is shared with `RideDetailSheet`, whose header is tile + name/park/status + Must-Do star, then a four-button action row (Rode It, My Day, Alert, Return) and grouped cards. The map's location button bumps `StyledMapUIView.recenterRequest`, which centers on MapKit's blue-dot fix (falls back to `LocationService`).
- Each park has a **persisted ride catalog** (UserDefaults `rideCatalog_<parkId>`, refreshed once per calendar day from `/children`) that supplies the roster and GPS coordinates; live data fills in wait/status. Rides missing from live data render as CLOSED (red ✗ badge; DOWN gets orange ⚠) instead of disappearing when a park closes. Schedules fetch once per park per session; only live data refetches each cycle. `allRides` is a stored property rebuilt once per refresh — don't turn it back into a computed join.

**Wait-time recording** (feeds predictions):
`ParkMapView.onChange(of: viewModel.lastRefreshed)` → `WaitTimeRecorder.shared.record(rides:context:)` after every foreground refresh; `BackgroundRefreshService` (BGAppRefreshTask, ≥1 h cadence) delegates to the same recorder for background coverage. The recorder throttles snapshots to one per ride per 10 minutes, tracks DOWN transitions via `UserDefaults` `lastStatus_<rideId>` keys (shared by both paths), and prunes at most every 6 h (90-day snapshot retention, 24 h cull of orphaned open downtimes).

**Bucket list** is seeded once on first launch:
`BucketListService.shared.seedIfNeeded(context:)` (called from `ParkTracApp.task`) reads `allSeedRestaurants` and `allSeedHotels` from `SeedData.swift` and inserts `BucketRestaurant` / `HotelStay` records that don't yet exist (insert-only, keyed by name — user-added custom entries survive).

**Deep links**: `thrilltrack://` (Info.plist `CFBundleURLTypes`) → `DeepLink` / `DeepLinkRouter.shared` (`Services/DeepLinkRouter.swift`). Routes: `waittimes`, `ride/<id>`, `timer` (active wait timer's ride), `plan`, `dining`, `settings`, `bucketlist`, `parking` (sets `showParking`; `ContentView` presents `ParkingSheet` over any tab). Empty states use these for their call-to-action buttons (e.g. "Open Wait Times"). `ContentView` consumes `router.pending` (switches `AppTab`); `ParkMapView` opens `pendingRideId`; `StatsView` pushes `MyDiningView` on `showDining`. Sources: `.onOpenURL`, Live Activity `widgetURL` (the widget builds the same URL strings itself — it doesn't compile the router), notification `userInfo["deepLink"]` via `NotificationDelegate` (set in `ParkTracApp.init`, also shows banners in the foreground), taps on `ReturnTimeBanner` / `WaitTimerBanner`, and Home Screen quick actions (Info.plist `UIApplicationShortcutItems`, whose `type` is a deep-link host → `QuickActions`; cold launch via `AppDelegate.application(_:configurationForConnecting:options:)`, warm via `QuickActionSceneDelegate`). Navigate by calling `DeepLinkRouter.shared.open(...)` rather than adding new ad-hoc flags.

**Lightning Lane watcher** (notify-only — the app never books; auto-booking would need Disney's private API/credentials and violates their ToS): `LiveDataEntry.queue.RETURN_TIME` / `PAID_RETURN_TIME` → `DisplayRide.multiPass` / `singlePass` (`LightningLaneInfo`). `LightningLaneWatchService.shared` keeps today's `LightningLaneWatch`es in UserDefaults (per device, not CloudKit, so paired phones don't double-alert) and `check(rides:)` runs after every foreground refresh (`WaitTimesViewModel.loadAllParksInGroup`) and every `BackgroundRefreshService` run; it notifies when a Multi Pass return opens inside the window, then only for earlier returns. UI: `LightningLaneSection` in `RideDetailSheet`, LL line + bell on `RideCardView`, "Watching for Lightning Lane" section in My Day. Auto-refresh keeps running off the Wait Times tab while a watch is active.

**Return times / DAS & AAP**: every booked return (LL, Express Now, DAS, AAP) is recorded through `ReturnTimeLogger.log` (`Services/ReturnTimeLogger.swift`) — PlanItem + Live Activity + reminder. DAS/AAP (`AccessPass`) are open-ended: the activity counts down to the return *start* ("Return at…") and `scheduleReturnReady` fires when it opens; their default return comes from `AccessPass.returnDelayMinutes` — AAP: posted wait < 30 min → immediate, else posted wait − 15 min; DAS: posted wait. ThrillTrack never books on Disney/Universal systems — "Book in … App" calls `BookingApp.open()`: the user's "Open Disney App"/"Open Universal App" Shortcut if enabled in Settings → Booking Apps, else the website (their sites do not hand off to the apps; guessed URL schemes were tried and failed on device). Lightning Lane gets the same "I Booked It" flow: `LightningLaneSection` and the `LL_WATCH_OPENING` notification action call `ReturnTimeLogger.logLightningLaneNow` with the return window ThrillTrack saw, which also stops that ride's watch. Wait-drop alerts for DAS/AAP holders carry notification actions (categories `WAIT_DROP_DAS` / `WAIT_DROP_AAP`, registered in `NotificationDelegate.registerCategories()`): open the booking app, or "I Booked It" which logs in the background via `ReturnTimeLogger.logAccessPassNow`.

**Instant alerts (server)**: `server/` is a Deno Deploy app (TypeScript; `deno task test`; setup in `server/README.md`), live at `https://thrilltrack-alerts.mattgottfried.deno.net` and redeployed on every merge to the default branch. It polls themeparks.wiki `/live` every minute for parks with active watches and sends APNs pushes. `InstantAlertsService` (`Services/InstantAlertsService.swift`, also holds `ReopenWatchService` and the push-token `AppDelegate`) uploads this phone's watches (`POST /v1/sync`: LL watches, active `RideAlert`s with `parkId`, reopen watches) and applies what the server already fired (`states`). While the server `covers(id)` a watch, the local checks (`LightningLaneWatchService.check`, `NotificationService.checkAlerts`, `ReopenWatchService.check`) skip it — no double alerts; if sync fails they take over. **The alert rules exist twice** — `server/logic.ts` mirrors the Swift (LL `alertStart`, AAP/DAS return delay, notification text, `NotificationKeys`/categories in the payload); change both together. `ServerWatch` field names are the server's contract. Push env: DEBUG → sandbox, else production. `RideAlert.parkId/parkName/resortRaw` are optional (older alerts stay local-only). The server also records **community wait history** (`server/history.ts`): every ride at the four resorts every 10 min (Deno KV, 60 days), served as `GET /v1/history?parkId&weekday` (typical wait per local hour). `CommunityHistoryService` (`Services/CommunityHistory.swift`) fetches it once per park per park-local day (after each foreground refresh in `ParkMapView`) and `RideProfile.waitsByHour` uses it after this phone's own history and before the live×park-curve estimate.

**Ride heights** (`Services/RideMetadata.swift`): `rideMetadata` (Orlando, inches), `tokyoDisneyRideMetadata` and `universalJapanRideMetadata` (published cm, some with `maxHeightCm`). Always look up with `RideMetadata.info(for:resort:)` — per-resort table (names like "Space Mountain" collide across resorts), then punctuation-insensitive, then a contained-name match for API variants. Display with `HeightFormat` (cm at Japan resorts via `RideMetadata.prefersMetric`). Japan values were compiled from published requirements in Sept 2026 and need confirming in the parks. Japan entries don't set `lightningLane` — return passes there come from live data.

**USJ Area Timed Entry**: `AreaEntry` + `ReturnTimeLogger.logAreaEntry` log a Super Nintendo World (etc.) entry window as a timed "ll" PlanItem (rideId `area-<name>`) with Live Activity, an "entry is open" notification (`scheduleAreaEntryOpen`) and the usual closing-soon reminder. UI: `AreaEntrySheet` (in `BookReturnTimeSheet.swift`) from My Day at USJ.

**Car locator** (`Services/ParkingService.swift`, `Views/WaitTimes/ParkingSheet.swift`): one `ParkingSpot` per resort (GPS + lot/section/level/row picked from `ParkingLots` menus like the Disney/Universal apps, + a free note; Japan has no lot menus yet), stored as JSON in iCloud KVS `parkingSpots` (+ UserDefaults mirror) so both phones see it; valid for `ParkingSpot.lifetime` (20 h), then hidden. The row-sign photo stays on the device (Application Support/Parking). Saving uses `PreciseLocator` (best-accuracy one-shot, ≤8 s) because `LocationService` is deliberately coarse. Entry points all call `DeepLinkRouter.shared.open(.parking)`: car button + car pin (`ParkingPointAnnotation`) on the Wait Times map, and the Parking row in My Day. "Walk There" opens Apple Maps walking directions; distance text is `ParkingDistance`. `ParkingReminder` schedules a local "parks close at…" notification 30 min before the resort's latest regular (non-ticketed) close; it's re-armed from `ParkMapView`'s refresh and from the sheet (toggle `parkingCloseReminder`, default on).

**Good Time to Ride** (`Services/GoodTimeToRide.swift`): per-ride "usual" wait — this phone's `WaitTimeRecord`s at the same hour (±1 h) on ≥2 earlier days (≥6 samples), else the server's community history for this hour (`Basis.typicalForDay`, via `CommunityHistoryService`), else median of today's earlier samples (last 30 min excluded). A deal = operating, usual ≥ 20, wait ≤ 65% of usual and ≥ 15 min saved. `GoodTimeService.update` runs after every foreground refresh (`ParkMapView`) and background refresh; green badge on `RideCardView`, "Good Time to Ride" strip atop the ride list (Must-Dos first), and a once-per-ride-per-day notification for Must-Dos (Settings toggle `goodTimeAlerts`). Works for rides this phone has never recorded once the community history has data.

**Trip Planner** (`Services/TripService.swift`, `Views/Stats/TripPlannerView.swift`): one `Trip` (name, dates, resorts, checklist) in iCloud KVS `tripPlan` so both phones share it; `TripCountdown` drives the My Day countdown row and the Stats link. `CurrencyConverter` keeps ¥ per $1 (Frankfurter/ECB, refreshed ≤ daily, or set by hand); Spending at JPY resorts shows "≈ $" beside yen, and Add Purchase uses ¥.

**Smart Planner** (`Views/Planner/SmartPlannerView.swift`, engine in `Services/DayPlanBuilder.swift`): `RideProfile.waitsByHour` gives each ride its own expected wait per hour (this phone's median for that hour over 30 days, else the live wait scaled by the park's `CommunityBaselines` curve; current hour = live). `DayPlanBuilder.build` is a greedy scheduler (walk + expected wait, penalized when the ride gets shorter later) that never moves `FixedEvent`s (chosen shows, today's `DiningReservation`s, meals/breaks from the request) and stops at park close. The guest picks rides/shows (+ interests, optional notes); **"Plan with Apple Intelligence"** sends the picks with each ride's expected waits by hour, shows, dining and close to `PlannerAI` (Foundation Models, iOS 26+, `@Generable` → order + meals/breaks from notes + interests + a summary), and `DayPlanBuilder.build(ordered:)` times it — the model orders, ThrillTrack times (`resolveOrder` keeps every pick). Without Apple Intelligence the greedy builder plans.

**Genie-style live plan** (`Services/ItineraryService.swift`, `Views/Planner/NextUpCard.swift`, `Views/WaitTimes/TipBoardView.swift`): "Start Plan" saves a `DayItinerary` (picks, shows, `Interest`s, notes, AI order/summary/extras, done/skipped) in iCloud KVS `dayItinerary` so both phones share it. `ItineraryService.replan` runs after every foreground refresh (from the user's location, live waits; RideLogs today mark rides done) and builds `live` from now to close; `NextUpCard` (Wait Times list top + My Day) shows the next stop with Done/Skip and `InterestSuggestions` (interest-matching rides with short waits now). My Day lists the live plan ("Today's Plan · Updates Live"). Tip Board (map button / My Day): Must-Dos + picks with wait now, usual now (`GoodTimeToRide.usual`) and best hour today (`TipBoard.best` over the ride's profile). FoundationModels is weak-linked (`OTHER_LDFLAGS -weak_framework FoundationModels`) and every use is behind `canImport` + `#available(iOS 26.0, *)` — the app still supports iOS 17. No Claude/server planner (user chose Apple Intelligence only).

**Future days**: the Smart Planner's Day picker plans up to 60 days ahead — `WaitTimesViewModel.schedule(for:on:)` (pass `FutureDay.noon(day)`) for hours, `CommunityHistoryService.load(parkIds:weekday:)` + `waitsByHour(rideId:parkId:weekday:)` for that weekday's typical waits, `RideProfile.waitsByHour(…pinCurrentHour: false)`, shows moved from today's schedule (`FutureDay.moving`), no rain. "Save Plan" → `ItineraryService.saveUpcoming` (iCloud KVS `upcomingItineraries`); `promoteIfDue` (init, KVS change, every `replan`) turns the day's plan into `itinerary` unless one is already running today (`ItineraryStore`, pure). Fixed lists / Add to My Day write `PlanItem.date` = that day; My Day's "Coming Up" section lists saved plans and future days (`FutureDayView`).

**Real vs posted wait** (`WaitReality` in `WaitTimePredictionService.swift`): median actual÷posted from Rode It! stopwatch logs — this ride's ≥2 timed rides, else ≥5 timed rides at the resort; `RideDetailSheet` shows "You usually wait ~X (posted Y)" when it differs by ≥5 min, and the Wait Forecast repeats it.

**Rain plan** (`Services/RainForecast.swift`): `RainForecastService` pulls Open-Meteo hourly rain chance for the resort (`ParkGroup.weatherCoordinate`, ≤ every 30 min from `ParkMapView`'s refresh); hours ≥50% are wet. `DayPlanBuilder.build(…wetHours:)` adds `rainPenalty` to outdoor rides in wet hours (`PlanRide.isIndoor` from `RideMetadata.isIndoor` — dark rides/simulators/shows + `indoorOverrides`), `PlannerAI` prompts mark indoor rides and rain hours, `RainHeadsUp` shows on Next Up / Smart Planner, and a once-a-day notification fires 15–60 min before the rain (Settings toggle `rainAlerts`).

**Shows**: rows in `ShowsListView` open `ShowDetailSheet` (same file): today's showtimes, a per-showing 15-min reminder (local notification id `show-<id>-<epoch>`), and Add to My Day with `prefillShow`.

**Add to My Day** (`Views/Planner/AddPlanItemView.swift`): one screen — type chips, the resort's rides (multi-select, `WaitTile` badges, closed rides dimmed) or shows inline by park, then When chips (Anytime / Now / Best ~time from `WaitForecast.call` / showtimes / Pick a time). Opened from a ride or show it starts compact (`.medium`). LL returns save through `ReturnTimeLogger.log`. Defaults in `AddPlanDefaults`.

**Siri** (`Services/SiriIntents.swift`, shortcuts in `RideWaitTimeIntent.swift`'s `ParkTracShortcuts`): "What should I ride next" (`NextRideAdvisor`: Must-Do good-time deals → any deal → Must-Dos by wait → rest), "Where did I park", "Save my parking spot" (opens the sheet), "Plan my day" (asks what to include, opens the Smart Planner via `thrilltrack://planner` + `DeepLinkRouter.plannerRequest`), plus the ride wait lookup.

**Must-Do down alerts**: `MustDoDownService` (in `InstantAlertsService.swift`) keeps the Must-Do rides with park ids (refreshed in `ParkMapView`'s refresh), syncs them as server watches of kind `down` (`mustdo-<rideId>`), and alerts locally when the server isn't covering. Rule `MustDoDown.transition` mirrors `downTransition` in `server/logic.ts` (DOWN → "is down", then OPERATING → "back up", CLOSED resets quietly). Settings toggle `mustDoDownAlerts`.

**Crowd calendar**: past days come from the server's history (`GET /v1/days?resort=<apiSlug>` → each park's 10 AM–6 PM average per day; `CrowdHistoryService` in `CommunityHistory.swift`, cached 6 h); the next 14 days are predicted from ≥2 of the same weekday in the last 4 weeks; otherwise `CrowdCalendarService`'s seasonal estimate (`CrowdHistory.source`). `CrowdDayDetail` says which.

**Day recap** (`Views/Stats/DayRecapView.swift`): `DayRecapBuilder` (pure) from RideLogs + purchases, steps from `CMPedometer` (`StepCounter`, ~7 days; `NSMotionUsageDescription`), shareable `RecapCard` image (`ImageRenderer`) or `DaySummary` text. My Day toolbar ✨ and Stats → Recaps (`DayRecapListView`).

**Live Activities** (`ThrillTrackActivityAttributes` — compiled into app + widget; views in `TrillTrackWidget/TrillTrackWidgetLiveActivity.swift`, one `ActivityStyle` per mode): return time (timed passes get `windowStart` → progress bar), wait stopwatch (bar toward the posted wait), dining, rope drop, next booking, and **Park Day** (`.parkDay`): `ItineraryService.replan` → `LiveActivityManager.updateParkDay` with `ParkDayActivity.state` (Next Up stop, wait, detail, then, progress, rain); ended by End Plan / no plan; Settings toggle `parkDayActivity`. New `ContentState` fields must stay optional with defaults. Second pass: `ResortPalette` (from attributes `resortRaw`) colors, big-number layout, Park Day `upcoming` timeline (3 stops), and buttons — `Services/LiveActivityIntents.swift` (compiled into app AND widget, pbxproj `AA…1B8`/`1BA`) defines `LiveActivityIntent`s that call `LiveActivityActions.handler`, set by `LiveActivityActionHandler.register()` in `ParkTracApp.init` (Done/Skip → `ItineraryService`, I'm On → RideLog from the persisted timer + `.waitTimerChangedExternally`, Used It → tick the PlanItem). `LiveActivityManager.end…` also ends activities left from before a relaunch.

**Time Sensitive notifications**: entitlement `com.apple.developer.usernotifications.time-sensitive` (App ID capability must be on). "Act now" alerts set `interruptionLevel = .timeSensitive` — wait drops, LL openings, reopen, return ready, area entry, LL closing, parking close (`NotificationService`, `ParkingReminder`); server pushes send `interruption-level: time-sensitive`. Confirmations and pass-renewal reminders stay normal.

**Dining log**: `MyDiningView` (reached from the Stats tab) is the active dining log — reservations (`DiningReservation`) plus visited `BucketRestaurant`s. There is no separate `Restaurant` model (the legacy one was removed).

### Key Models

| File | Type | Purpose |
|------|------|---------|
| `BucketRestaurant.swift` | SwiftData `@Model` | Bucket list restaurant (seeded + custom), dual ratings, photos |
| `HotelStay.swift` | SwiftData `@Model` | Hotel bucket entry, includes `@Attribute(.externalStorage) [Data]` photos |
| `DiningReservation.swift` | SwiftData `@Model` | Upcoming/past dining reservation |
| `RideLog.swift` | SwiftData `@Model` | "Rode It!" log entry (posted vs actual wait) |
| `PlanItem.swift` | SwiftData `@Model` | My Day planner item |
| `WaitTimeRecord.swift` | SwiftData `@Model` | Wait time snapshot per ride (telemetry store) |
| `DowntimeRecord.swift` | SwiftData `@Model` | DOWN interval per ride (telemetry store) |
| `ParkModels.swift` | Plain structs | API response types + `DisplayRide`/`DisplayShow` (live data + GPS merged) |
| `ParkDestination.swift` | Enum + struct | `ParkGroup` enum (disney/universal) with `destinationId`; `ParkTheme` colors |

All persisted models are registered in `PersistenceController.userModels` / `telemetryModels`. New CloudKit-synced attributes must be optional or defaulted.

### API

Base URL: `https://api.themeparks.wiki/v1` (public, no auth)

| Endpoint | Used by |
|----------|---------|
| `GET /entity/{destinationId}/children` | `fetchDestinationChildren` — returns `PARK` entities |
| `GET /entity/{parkId}/children` | `fetchAttractionChildren` — returns `ATTRACTION` entities with GPS |
| `GET /entity/{parkId}/live` | `fetchLiveData` — returns current wait times and statuses |
| `GET /entity/{parkId}/schedule` | `fetchSchedule` — park operating hours |

### Predictions (`WaitTimePredictionService.swift`)

Pure struct (no persistence). Returns `PredictionResult` containing:
- Community baseline curves (bundled `CommunityBaselines.json`, always available)
- Personal history average (from `WaitTimeRecord`, requires ≥5 data points)
- Closure duration estimate (from `DowntimeRecord`, requires ≥3 completed records)

Displayed in `RidePredictionView` (Swift Charts) inside `RideDetailSheet` — for operating rides it's the **Wait Forecast**: bars from `RideProfile.waitsByHour` (same numbers as the Smart Planner/Tip Board) over today's open hours, with `WaitForecast.call` (go now vs. wait until a later hour that saves ≥10 min), `WaitForecast.trend` (next hour) and usual-for-now (`GoodTimeToRide.usual`); touch the chart to read any hour. Down rides keep the closure progress view.

### Naming Conventions

- `allSeedRestaurants` / `allSeedHotels` — global arrays in `SeedData.swift` (prefixed `all` to avoid shadowing `BucketListService` method names `seedRestaurants` / `seedHotels`)
- Parks are runtime-fetched `ParkEntity` values, not static — there is no `ParkGroup.parks`.
- Today's guests are `AppState.todayGuestNames` (keyed by `Guest.name`, stored per day, reset via `reloadTodayGuestsIfNewDay()` on app activation). Never key anything by `persistentModelID.hashValue` — Swift randomizes hashes per launch. Onboarding's party names are `AppState.partyMembers` (`namedPartyMembers` drops the "Me" placeholder); lists of names render with `NameList.format`.
- Wife's name is **Heather**. The two rating-column labels come from `AppState.raterOneLabel` / `raterTwoLabel` (editable in Settings, iCloud KVS-synced, default "Matt" / "Heather"); the stored fields stay `mattRating` / `wifeRating`. Don't hardcode the names in new UI.
- `SeedData.swift` still contains Matt & Heather's personal `isVisited` / ratings for reference, but `BucketListService` deliberately imports only the catalog fields — never seed personal history into new installs.

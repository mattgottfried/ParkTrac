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

There are no automated tests. Verification is done by building in Xcode and running in the simulator.

**When adding new Swift source files**, the file MUST be registered in `ParkTrac.xcodeproj/project.pbxproj` in four places: `PBXBuildFile`, `PBXFileReference`, the owning `PBXGroup`'s `children`, and `PBXSourcesBuildPhase`. Missing this step causes "No such module" or linker errors at build time. When deleting files, remove all four entries. The project uses synthetic sequential IDs (`AA00…`) — take the next unused pair.

## Architecture

**Target**: iOS 17+, SwiftUI, `@Observable` macro (not `ObservableObject`), SwiftData for persistence.

### Five-Tab Structure (`ContentView.swift`)
1. **Wait Times** — `ParkMapView` — full-screen MapKit map with live ride wait time pins + a bottom panel listing rides/shows
2. **My Day** — `DayPlannerView` — today's plan (rides, dining, Lightning Lane windows, guests)
3. **Bucket List** — `BucketListView` — restaurants/hotels checklists with filters, sort, custom entries, and photos
4. **Stats** — `StatsView` — hub linking dining log (`MyDiningView`), ride counter, spending, crowd calendar, badges, etc.
5. **Settings** — `SettingsView` — prefs, resort switch, passes, tools, storage/sync status

A banner stack (resort switcher, blockout, return-time, wait-timer) sits above the TabView. The app has **no third-party dependencies** — no SPM packages (GoogleMobileAds was removed).

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
- Each park has a **persisted ride catalog** (UserDefaults `rideCatalog_<parkId>`, refreshed once per calendar day from `/children`) that supplies the roster and GPS coordinates; live data fills in wait/status. Rides missing from live data render as CLOSED (red ✗ badge; DOWN gets orange ⚠) instead of disappearing when a park closes. Schedules fetch once per park per session; only live data refetches each cycle. `allRides` is a stored property rebuilt once per refresh — don't turn it back into a computed join.

**Wait-time recording** (feeds predictions):
`ParkMapView.onChange(of: viewModel.lastRefreshed)` → `WaitTimeRecorder.shared.record(rides:context:)` after every foreground refresh; `BackgroundRefreshService` (BGAppRefreshTask, ≥1 h cadence) delegates to the same recorder for background coverage. The recorder throttles snapshots to one per ride per 10 minutes, tracks DOWN transitions via `UserDefaults` `lastStatus_<rideId>` keys (shared by both paths), and prunes at most every 6 h (90-day snapshot retention, 24 h cull of orphaned open downtimes).

**Bucket list** is seeded once on first launch:
`BucketListService.shared.seedIfNeeded(context:)` (called from `ParkTracApp.task`) reads `allSeedRestaurants` and `allSeedHotels` from `SeedData.swift` and inserts `BucketRestaurant` / `HotelStay` records that don't yet exist (insert-only, keyed by name — user-added custom entries survive).

**Deep links**: `thrilltrack://` (Info.plist `CFBundleURLTypes`) → `DeepLink` / `DeepLinkRouter.shared` (`Services/DeepLinkRouter.swift`). Routes: `waittimes`, `ride/<id>`, `timer` (active wait timer's ride), `plan`, `dining`, `settings`. `ContentView` consumes `router.pending` (switches `AppTab`); `ParkMapView` opens `pendingRideId`; `StatsView` pushes `MyDiningView` on `showDining`. Sources: `.onOpenURL`, Live Activity `widgetURL` (the widget builds the same URL strings itself — it doesn't compile the router), notification `userInfo["deepLink"]` via `NotificationDelegate` (set in `ParkTracApp.init`, also shows banners in the foreground), and taps on `ReturnTimeBanner` / `WaitTimerBanner`. Navigate by calling `DeepLinkRouter.shared.open(...)` rather than adding new ad-hoc flags.

**Lightning Lane watcher** (notify-only — the app never books; auto-booking would need Disney's private API/credentials and violates their ToS): `LiveDataEntry.queue.RETURN_TIME` / `PAID_RETURN_TIME` → `DisplayRide.multiPass` / `singlePass` (`LightningLaneInfo`). `LightningLaneWatchService.shared` keeps today's `LightningLaneWatch`es in UserDefaults (per device, not CloudKit, so paired phones don't double-alert) and `check(rides:)` runs after every foreground refresh (`WaitTimesViewModel.loadAllParksInGroup`) and every `BackgroundRefreshService` run; it notifies when a Multi Pass return opens inside the window, then only for earlier returns. UI: `LightningLaneSection` in `RideDetailSheet`, LL line + bell on `RideCardView`, "Watching for Lightning Lane" section in My Day. Auto-refresh keeps running off the Wait Times tab while a watch is active.

**Return times / DAS & AAP**: every booked return (LL, Express Now, DAS, AAP) is recorded through `ReturnTimeLogger.log` (`Services/ReturnTimeLogger.swift`) — PlanItem + Live Activity + reminder. DAS/AAP (`AccessPass`) are open-ended: the activity counts down to the return *start* ("Return at…") and `scheduleReturnReady` fires when it opens; their default return comes from `AccessPass.returnDelayMinutes` — AAP: posted wait < 30 min → immediate, else posted wait − 15 min; DAS: posted wait. ThrillTrack never books on Disney/Universal systems — "Book in … App" calls `BookingApp.open()`: the user's "Open Disney App"/"Open Universal App" Shortcut if enabled in Settings → Booking Apps, else the website (their sites do not hand off to the apps; guessed URL schemes were tried and failed on device). Lightning Lane gets the same "I Booked It" flow: `LightningLaneSection` and the `LL_WATCH_OPENING` notification action call `ReturnTimeLogger.logLightningLaneNow` with the return window ThrillTrack saw, which also stops that ride's watch. Wait-drop alerts for DAS/AAP holders carry notification actions (categories `WAIT_DROP_DAS` / `WAIT_DROP_AAP`, registered in `NotificationDelegate.registerCategories()`): open the booking app, or "I Booked It" which logs in the background via `ReturnTimeLogger.logAccessPassNow`.

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

Displayed in `RidePredictionView` (Swift Charts) inside `RideDetailSheet`.

### Naming Conventions

- `allSeedRestaurants` / `allSeedHotels` — global arrays in `SeedData.swift` (prefixed `all` to avoid shadowing `BucketListService` method names `seedRestaurants` / `seedHotels`)
- Parks are runtime-fetched `ParkEntity` values, not static — there is no `ParkGroup.parks`.
- Wife's name is **Heather**. The two rating-column labels come from `AppState.raterOneLabel` / `raterTwoLabel` (editable in Settings, iCloud KVS-synced, default "Matt" / "Heather"); the stored fields stay `mattRating` / `wifeRating`. Don't hardcode the names in new UI.
- `SeedData.swift` still contains Matt & Heather's personal `isVisited` / ratings for reference, but `BucketListService` deliberately imports only the catalog fields — never seed personal history into new installs.

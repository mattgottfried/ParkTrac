# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a native iOS/iPadOS app. There is no CLI build — use Xcode or `xcodebuild`:

```bash
# Build for simulator (no signing required)
xcodebuild -project ParkTrac.xcodeproj -scheme ParkTrac -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run on simulator
xcodebuild -project ParkTrac.xcodeproj -scheme ParkTrac -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath /tmp/ParkTracBuild build
```

There are no automated tests. Verification is done by building in Xcode and running in the simulator.

**When adding new Swift source files**, the file MUST be registered in `ParkTrac.xcodeproj/project.pbxproj` in three places: `PBXBuildFile`, `PBXFileReference`, and `PBXSourcesBuildPhase`. Missing this step causes "No such module" or linker errors at build time.

## Architecture

**Target**: iOS 17+, SwiftUI, `@Observable` macro (not `ObservableObject`), SwiftData for persistence.

### Three-Tab Structure (`ContentView.swift`)
1. **Wait Times** — `ParkMapView` — full-screen MapKit map with live ride wait time pins + a non-dismissable bottom sheet listing rides
2. **My Dining** — `RestaurantListView` — personal log of restaurants visited, with Matt + Heather star ratings
3. **Bucket List** — `BucketListView` — checklist of every restaurant and hotel at both resorts

### Data Flow

**Live wait times** flow through:
`ParkAPIService` (actor) → `WaitTimesViewModel` (@Observable) → `ParkMapView` + bottom sheet

- Parks are discovered **dynamically** at launch: `ParkAPIService.fetchDestinationChildren(destinationId:)` returns park IDs — there are **no hardcoded park entity IDs**. Only the destination IDs in `ParkGroup` are hardcoded.
- `WaitTimesViewModel.loadAllParks()` fetches parks for both Disney and Universal concurrently, then auto-selects the first park. Called from `ParkMapView.task`.
- Rides auto-refresh every 60 seconds via a `Task.sleep` loop in `startAutoRefresh()`.
- After each load, `WaitTimeRecorder.shared.record(rides:parkId:context:)` persists snapshots and tracks DOWN transitions.

**Bucket list** is seeded once on first launch:
`BucketListService.shared.seedIfNeeded(context:)` (called from `ParkTracApp.task`) reads `allSeedRestaurants` and `allSeedHotels` from `SeedData.swift` and inserts `BucketRestaurant` / `HotelStay` records that don't yet exist.

### Key Models

| File | Type | Purpose |
|------|------|---------|
| `Restaurant.swift` | SwiftData `@Model` | Personal dining log entry |
| `BucketRestaurant.swift` | SwiftData `@Model` | Bucket list restaurant (pre-seeded) |
| `HotelStay.swift` | SwiftData `@Model` | Hotel bucket list entry, includes `[Data]` for photos |
| `WaitTimeRecord.swift` | SwiftData `@Model` | Hourly wait time snapshot per ride |
| `DowntimeRecord.swift` | SwiftData `@Model` | Tracks each DOWN interval for a ride |
| `ParkModels.swift` | Plain structs | API response types + `DisplayRide` (live data + GPS merged) |
| `ParkDestination.swift` | Enum + struct | `ParkGroup` enum (disney/universal) with `destinationId`; `ParkTheme` colors |

All five SwiftData models are registered in `ParkTracApp.swift`'s `ModelContainer`.

### API

Base URL: `https://api.themeparks.wiki/v1` (public, no auth)

| Endpoint | Used by |
|----------|---------|
| `GET /entity/{destinationId}/children` | `fetchDestinationChildren` — returns `PARK` entities |
| `GET /entity/{parkId}/children` | `fetchAttractionChildren` — returns `ATTRACTION` entities with GPS |
| `GET /entity/{parkId}/live` | `fetchLiveData` — returns current wait times and statuses |

### Predictions (`WaitTimePredictionService.swift`)

Pure struct (no persistence). Returns `PredictionResult` containing:
- General wisdom baselines (time-of-day multipliers, always available)
- Personal history average (from `WaitTimeRecord`, requires ≥5 data points)
- Closure duration estimate (from `DowntimeRecord`, requires ≥3 completed records)

Displayed in `RidePredictionView` using Swift Charts.

### Naming Conventions

- `allSeedRestaurants` / `allSeedHotels` — global arrays in `SeedData.swift` (prefixed `all` to avoid shadowing `BucketListService` method names `seedRestaurants` / `seedHotels`)
- Park pickers in `AddRestaurantView` and `EditRestaurantView` use **hardcoded string arrays** (`parkOptions` / `editParkOptions`) — not `ParkGroup.parks`, which does not exist. Parks are runtime-fetched `ParkEntity` values, not static.
- Wife's name is **Heather** (used in labels throughout the UI).

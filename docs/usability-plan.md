# ThrillTrack usability plan — status

| Phase / item | Status | PR |
|---|---|---|
| 1. Nested nav stacks, undo for deletes, LL swipe, Rides/Shows memory | Done | #21 |
| 2. Haptics, ride long-press menu, sort/filter, stale-data pill | Done | #21 |
| Seed-data fix, editable reviewer names, reset dining | Done | #21 |
| Apple Maps base layer (CARTO needed a key) | Done | #21 |
| Export-compliance key | Done | #21 |
| 3. Deep links (Live Activities, notifications, banners) | Done | #22 |
| 4. VoiceOver + Dynamic Type; event names in park hours | Done | #22 |
| Lightning Lane watcher | Done | #23 |
| AAP/DAS assist ("I Booked It", return reminders) | Done | #24, #27 |
| Open booking apps via Shortcut | Done | #25, #26 |
| LL "I Booked It" | Done | #26 |
| Tests, pin long-press menu, Must-Do down haptic, day summary share, CSV export, Settings cleanup, walking time | Done | this PR |

What's next lives in `ideas.md`. The original plan follows for reference.

---

# ThrillTrack: usability and quality-of-life plan

## Context
The feature set is broad: five tabs, Live Activities, predictions, bucket list, and stats. What's missing is polish that makes the app quick to use one-handed in a crowded park. A survey of the code found these gaps:
- **No haptics anywhere.** There are no `sensoryFeedback` or `UIFeedbackGenerator` calls.
- **No accessibility labels.** `accessibilityLabel` appears 0 times. The map pins are UIKit views with a fixed 13pt font, and there are many hard-coded `.font(.system(size:))` calls.
- **No context menus or undo.** Deletes in the Planner, Dining, Spending, Ride Counter and Visit History happen right away with no way to undo.
- **Must-Do is hard to set.** A ride can only be starred from inside `RideDetailSheet`.
- **Nested navigation bug.** `StatsView.swift:191` pushes `DayPlannerView()`, which wraps its own `NavigationStack`. That puts a navigation stack inside a navigation stack (double nav bar, broken back button).
- **Wrong swipe role.** The Lightning Lane "Done" swipe (`DayPlannerView.swift:41`) uses `role: .destructive`, so it shows red like a delete.
- **Deep links go nowhere.** Tapping the Live Activity or a notification doesn't open the related tab or item. `TabView` has no `selection` binding.

Goal: a set of small, low-risk updates in phases. Each phase can ship as its own PR and gets verified in the simulator (the project has no tests).

---

## ▶ Current step: replace the CARTO tile overlay with Apple's own map

**Problem.** The Wait Times map is already an `MKMapView` (`StyledMapUIView` in `Views/WaitTimes/ParkMapView.swift`). But `Coordinator.addTiles(to:)` (~line 183) covers it with an `MKTileOverlay` of CARTO Voyager tiles (`https://a.basemaps.cartocdn.com/rastertiles/voyager/...`, `canReplaceMapContent = true`). CARTO now wants an API key, so the base map fails. Apple's MapKit needs no key and no Info.plist or entitlement changes, and it's the only other tile source in the app.

**Changes** (all in `ParkMapView.swift`, `StyledMapUIView`; no new files):
1. Delete `Coordinator.addTiles(to:)` and its two call sites (`makeUIView` and the satellite-off branch of `updateUIView`). Drop the `MKTileOverlay` branch from `mapView(_:rendererFor:)`, keeping the default `MKOverlayRenderer` fallback, or remove the method since nothing else adds overlays.
2. Add a `static func configuration(satellite: Bool) -> MKMapConfiguration` helper:
   - **Standard:** `MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)`, which gives the soft, low-contrast look the CARTO tiles had so the colored wait pins stand out. Set `pointOfInterestFilter = MKPointOfInterestFilter(including: [.restroom, .restaurant, .cafe, .parking])`. Apple's own attraction labels would clash with the ride pins, so they're hidden; restrooms and food stay useful in a park.
   - **Satellite:** `MKHybridMapConfiguration(elevationStyle: .realistic)` with the same POI filter. This replaces `mapType = .hybridFlyover`.
3. `makeUIView`: set `map.preferredConfiguration = Self.configuration(satellite: isSatellite)` and seed `context.coordinator.isSatellite = isSatellite`. That fixes a small existing bug where "Default to Satellite View" briefly showed the standard map first.
4. `updateUIView`: when `isSatellite` differs from `coordinator.isSatellite`, update the flag and set `map.preferredConfiguration` again. The `removeOverlays` / `mapType` juggling is no longer needed.
5. Leave the annotation, region and pin code untouched. Fix the stale comment ("CartoDB Voyager — … no API key required") by deleting it along with the function.

The satellite toggle button, `defaultMapIsSatellite`, and pins/annotations work as before. Light and dark mode now follow the system through MapKit.

**Verification (on the Mac):**
- Build, then open Wait Times.
- The base map should be Apple's muted map with park paths visible, and no blank or grey tiles.
- Pins sit on the right spots and are readable.
- The satellite toggle switches to hybrid and back.
- With "Default to Satellite View" on, launch opens straight into satellite.
- Dark mode looks right.

Pull/rebase before committing (the Mac session may have pushed), push to `claude/compassionate-brahmagupta-vrjn15`, and never force-push.

---

## DONE (90c3613): bug fix — personal dining history is seeded into every install

**Problem.** `Services/SeedData.swift` gives 47 `SeedRestaurant`s `isVisited: true` with Matt and Heather's real `mattRating` / `wifeRating`. `BucketListService.seedRestaurants` copies those fields into every new store. So a fresh simulator, a different Apple ID, or any other user starts with Matt and Heather's visits, and the Stats tab averages them. The "Matt" / "Heather" labels are also hardcoded. Hotel seeds carry no personal data.

**User decisions:** keep SeedData.swift as-is but stop importing the personal fields; make the two names editable in Settings; add a Settings button to reset dining history.

**1. Stop importing personal data** (`Services/BucketListService.swift`, `seedRestaurants`)
- Build each `BucketRestaurant(name:park:resort:category:)` without passing `isVisited`, `mattRating` or `wifeRating`, so they use the model defaults (false / 0).
- Add a comment saying `SeedData`'s visit/rating fields are kept on purpose for reference and must not be imported.
- `SeedData.swift` stays unchanged. Existing stores are unaffected, because seeding is insert-only and keyed by name|park.

**2. Editable reviewer names** (`Models/AppState.swift`)
- Add `var raterOneName: String` and `var raterTwoName: String` using the same iCloud KVS pattern as `sortRidesAlphabetically`:
  - a `didSet` that writes to `icloud`
  - init that reads KVS first, then falls back to `UserDefaults`
  - a line in `reloadFromiCloud()`
- Default to "Matt" / "Heather" when nothing is stored. Add a computed `displayName` helper that falls back to the default if the field is blank.
- Replace the literal labels with these names in:
  - `Views/Stats/StatsView.swift` `ratingsRow` (lines ~279–280)
  - `Views/BucketList/BucketRestaurantDetailView.swift` (`StarRatingView` labels, ~58–59)
  - `Views/BucketList/HotelDetailView.swift` (~63–64)
- These views already get `AppState` from the environment, or can take `@Environment(AppState.self)`. The detail views are sheets, which inherit the environment.
- Model field names (`mattRating` / `wifeRating`) stay the same, so there's no CloudKit schema change.
- Update CLAUDE.md's "Heather" note to say the names now come from Settings (default Matt / Heather).

**3. Settings: names and reset** (`Views/Settings/SettingsView.swift`)
- New "Dining & Hotel Ratings" section with two `TextField`s ("First reviewer", "Second reviewer") bound to `$state.raterOneName` / `raterTwoName`.
- In the same section, a destructive "Reset Dining History…" button that opens a `.confirmationDialog`. The dialog says it clears visited status and both ratings on every restaurant, and that if iCloud sync is on, the reset reaches every device on this Apple ID. On confirm:
  - fetch all `BucketRestaurant`
  - set `isVisited = false`, `visitDate = nil`, `mattRating = 0`, `wifeRating = 0`
  - `try? context.save()`
- Notes, photos, custom entries and hotels are left alone. `DiningReservation` records are untouched.
- Add `@Environment(\.modelContext)` to SettingsView.

**Verification (on the Mac):**
- Delete the app from the simulator, reinstall, and check that Stats dining shows no ratings and no restaurants are visited.
- Rate a restaurant and check that the labels use the names set in Settings; rename one and check the labels update in the Stats and detail views.
- Tap Reset Dining History and confirm; check that all visits and ratings clear.
- On an existing install (your phone), nothing changes until you reset.

**Coordinating with the Mac session.** The Mac Remote Control session is still checking Phase 2 and may push fixes to the same branch.
- Before editing, run `git pull --rebase origin claude/compassionate-brahmagupta-vrjn15` to pick up any of its commits.
- The fix touches StatsView, the two detail views, AppState, SettingsView and BucketListService. None of these were changed in Phase 2 except `AppState` (untouched in Phase 2) and StatsView (a one-line Phase 1 change), so conflicts are unlikely.
- Just before pushing, `git pull --rebase` again. If the push is rejected, pull again, rebase and retry.
- Never force-push.
- Tell the user the Mac session should `git pull` before its next build.

Commit to `claude/compassionate-brahmagupta-vrjn15` and push.

---

## Pending: have the Mac build and check Phases 1 and 2 through Remote Control (the user pastes the prompt)

Target: the Remote Control session `session_012Tb2vdMRv7FMbAqLMVdZTw` ("ParkTrac iPhone 16 build and verification"). It's connected and idle, and its checkout is at 4e7ecc6, one commit behind `7302bdb`.

1. Load `SendMessage` with ToolSearch and send the session this task:
   > Pull `claude/compassionate-brahmagupta-vrjn15` (`git pull`; it should be at 7302bdb). Build with `xcodebuild -project ParkTrac.xcodeproj -scheme ParkTrac -destination 'platform=iOS Simulator,name=iPhone 16' build`, then fix compile errors until the build is clean. Then boot the simulator, install the app, launch it, and check each item below, taking a screenshot of each:
   > - Stats → My Day, Spending and My Dining each show one nav bar, and back works.
   > - Deleting a plan item shows the Undo toast. Undo brings the item back; waiting 4s makes the delete stick.
   > - The Lightning Lane Done swipe is green.
   > - Long-pressing a ride card shows the menu, and each item opens the right screen.
   > - The filter button: Max wait 30 and Hide closed filter the list; sorting A–Z also flips the Settings toggle.
   > - The Rides/Shows choice survives a relaunch.
   >
   > Commit any fixes with clear messages and push to the same branch. Reply with a pass/fail list and what you changed.
2. If `SendMessage` can't reach it, fall back to having the user paste the same text into the session from the Claude Code app.
3. When results arrive (new commits on the branch, or a reply), review the fixes. Then continue to Phase 3 (deep links) if the user wants.

---

## Phase 2: implementation details (DONE in 7302bdb)

Work on branch `claude/compassionate-brahmagupta-vrjn15`, on top of Phase 1. This needs no new files, so no pbxproj edits.

**2a. Haptics** (`.sensoryFeedback`, iOS 17):
- `ParkMapView`:
  - `.selection`, triggered by `viewModel.filterPark?.id`, `showMustDoOnly` and `showTab`
  - `.success`, triggered by `viewModel.lastRefreshed`, only after a user pull-to-refresh. Use a `@State var userRefreshCount` that is bumped inside `.refreshable`, and trigger on that instead.
- `DayPlannerView.PlanItemRow`: `.success` when `item.isDone` flips to true, using the `trigger:condition:` form.
- `LLPassRow` and the Lightning Lane swipe Done: `.success`.
- `RideDetailSheet`: `.success` on Rode It save (the `toastMessage` set) and on the star toggle (`.selection`).
- DOWN warning: skipped. The plumbing through `WaitTimeRecorder` is too invasive for this phase.

**2b. Long-press menu on ride cards** (`ParkMapView.swift`, the `ForEach(displayedRides)` loop):
- Add `.contextMenu` to `RideCardView` with these items:
  - "Add to Must-Do" / "Remove from Must-Do": `appState.toggleWish(ride.id)`
  - "Add to My Day": presents the existing `AddPlanItemView(resort:prefillRide:prefillPark:)`
  - "Set Wait Alert": presents the existing `SetAlertSheet(ride:)`
  - "Details / Rode It": sets `selectedRide = ride`, which opens the existing `RideDetailSheet`
- Drive the presentation with a new `@State private var rideAction: RideMenuAction?`, an `Identifiable` enum with cases `.addToPlan(DisplayRide)` and `.alert(DisplayRide)`, plus one `.sheet(item:)`. The sheets are reused, so no `RideActions` extraction is needed.
- Add a `.contentShape(RoundedRectangle(...))` so the menu preview is the card shape.
- Map pins get no menu for now. They're UIKit annotation views, so a menu there would need `UIContextMenuInteraction`; deferred.

**2c. Sort and filter menu** (Wait Times panel):
- `WaitTimesViewModel`:
  - Add `enum RideSort: String, CaseIterable { case longestWait, shortestWait, name }` and replace `sortAlphabetical: Bool` with `var rideSort: RideSort`.
  - Update the comparator in `filteredRides`. `.shortestWait` puts operating rides first, ordered by wait ascending.
  - Keep `filteredRides` free of the hide/max filters, because `currentCrowdLevel` and `currentAverageWait` use it and must not be skewed.
- `ParkMapView`:
  - Add `@AppStorage("rideSort")`, `@AppStorage("hideClosedRides")` and `@AppStorage("maxWaitFilter") Int` (0 means off).
  - Apply the hide/max filters in `displayedRides` next to the existing Must-Do filter.
  - Put a `Menu` with `line.3.horizontal.decrease.circle` beside the `searchBar` TextField. It holds a sort Picker, a "Hide closed rides" Toggle, and a "Max wait" Picker (Any / 15 / 30 / 45 / 60). The icon shows `.fill` when any filter is active.
  - Update the empty-state text when filters hide everything ("No rides match your filters" plus a "Clear filters" button).
- Settings keeps its "Sort Rides A–Z" toggle, now mapped onto the same `rideSort` storage. `.task` and `.onChange` set `viewModel.rideSort` from `@AppStorage` instead of from `appState.sortRidesAlphabetically`. Change the Settings toggle to a Picker bound to `@AppStorage("rideSort")`, and one-time migrate the old bool (if `sortRidesAlphabetically` was true, set `rideSort = .name`). Check `AppState.sortRidesAlphabetically` for other users first and leave it in place if anything else reads it.

**2d. Out-of-date data warning** (`ParkMapView.panelHeader`):
- Wrap the "Updated … ago" line in `TimelineView(.periodic(from: .now, by: 30))`.
- If `now - lastRefreshed > 5 min`, show an orange capsule, "⚠︎ Wait times from N min ago — pull to refresh". Otherwise keep the current caption.
- No view-model change is needed; a partial failure already leaves `lastRefreshed` stale only when every park failed. To make partial failures stale too, set `lastRefreshed` only when `successCount > 0` in `loadAllParksInGroup` (`WaitTimesViewModel.swift:~264`). This matters because the recorder's `onChange(of: lastRefreshed)` would otherwise re-record the same stale data.

**Phase 2 verification:** same as the Verification section below, plus:
- long-press a ride → each menu item opens the right sheet
- set Max wait 30 → only rides ≤30 min and still open show
- sort changes in the menu are reflected in Settings, and the reverse
- airplane mode for 5+ min → orange warning appears
- haptics are felt on a device (the simulator gives no haptics)

Commit, push, and tell the user to rebuild on the Mac.

---

## Phase 1: Bugs and quick wins (small, high value): DONE in 4e7ecc6
1. **Fix the nested NavigationStack.** Pull `DayPlannerView`'s body into a `DayPlannerContent` view with no stack. The tab keeps `NavigationStack { DayPlannerContent() }`, and `StatsView` pushes `DayPlannerContent()`. Apply the same check to other views that are both tab roots and pushed destinations (`grep NavigationStack Views/` lists the candidates).
2. **Lightning Lane "Done" swipe.** Replace the red `.destructive` role with `.tint(.green)` and a `checkmark` icon.
3. **Undo for deletes.** Add a small `UndoToast` view plus a helper that snapshots the model's fields before the delete. Delete immediately, show "Deleted · Undo" for about 4 seconds, and re-insert if the user taps Undo. Apply it at every `context.delete` call in `DayPlannerView`, `MyDiningView`, `SpendingView`, `RideCounterView` and `VisitHistoryView`. `SetAlertSheet`'s replace-old-alert delete is internal and gets no toast.
4. **Remember the last park filter and the Rides/Shows tab.** Put `filterPark` id and `showTab` in `@AppStorage`, so reopening the app returns to the same view.

## Phase 2: Faster in-park interactions
1. **Haptics.** Add `.sensoryFeedback`, which is available on iOS 17:
   - `.success` for Rode It, Lightning Lane done, and plan item checked.
   - `.selection` for park chip, Must-Do filter, and Rides/Shows picker.
   - `.impact` for the pull-to-refresh finish.
   - `.warning` when a ride goes DOWN. The hook for this is `WaitTimeRecorder`'s status transition, surfaced through the view model.
2. **Context menus and swipes on ride cards.** In `ParkMapView.swift` (the `ForEach(displayedRides)` loop around line 564), add `.contextMenu` with:
   - Star/unstar Must-Do (toggles `appState.wishList`)
   - Add to My Day
   - Rode It
   - Set Alert
   - Start Wait Timer

   Reuse the actions that already exist in `RideDetailSheet` by extracting them into a shared `RideActions` helper. Add the same menu to the map pin tap (long press).
3. **Sort and filter menu on the ride list.** A toolbar `Menu` next to the search bar replaces the global Settings toggle for day-to-day use. It offers:
   - Sort by wait, name, or park area
   - Hide closed rides
   - Max wait: ≤15, ≤30 or ≤45 min
   - Must-Do only (moves the chip into the menu)

   Store the choices in `AppState` / `@AppStorage`, and keep `sortRidesAlphabetically` as the default.
4. **Stale data indicator.** When `lastRefreshed` is more than 5 minutes old (offline), show an orange "Showing data from 12 min ago" pill in `panelHeader` instead of the gray caption. Today, a partial failure is silent (`WaitTimesViewModel.swift:258`).

## Phase 3: Navigation and deep links: DONE (tab re-tap scrolls/recenters Wait Times only)
1. **Programmatic tab selection.** Add `AppState.selectedTab` (an enum) and bind it with `TabView(selection:)` in `ContentView.swift`.
2. **Deep links.** Add a `thrilltrack://` URL scheme in Info.plist and handle it with `.onOpenURL`, covering `ride/<id>`, `plan`, and `dining/<id>`. Wire the targets up:
   - Live Activity `widgetURL` in `TrillTrackWidget/TrillTrackWidgetLiveActivity.swift`
   - ride-alert notification taps
   - the banners (`ReturnTimeBanner`, `WaitTimerBanner`), which should jump to the relevant item
3. **Tap the tab again to scroll to top.** When the active tab is tapped again, scroll the ride list to the top and recenter the map on the resort's `defaultRegion`.

## Phase 4: Accessibility and Dynamic Type
1. **Accessibility labels.**
   - Map pins: set `isAccessibilityElement`, `accessibilityLabel` to "Space Mountain, 45 minute wait", and `accessibilityTraits = .button` in `RideAnnotationView.configure`.
   - `RideCardView`, `WaitBadgeView`, and the badges get combined elements with spoken wait and status.
   - Icon-only buttons (clear search, star, satellite toggle) get labels.
2. **Status isn't color-only.** Status is currently shown by color alone (green, yellow, red). Add the status word or an icon to the labels and to `WaitBadgeView`.
3. **Dynamic Type.** Swap text uses of `.font(.system(size:))` for text styles, or `@ScaledMetric` where a fixed size matters. The main files are `ContentView`, `WaitTimeAnnotation`, `RideDetailSheet`, `BadgesView` and `CrowdCalendarView`. Map pins stay fixed-size by design, but scale up at accessibility sizes via `UIFontMetrics`.
4. **Check at the largest size.** Test each tab at AX5 text size and fix truncation. Candidates are the park chips, `ParkHoursHeaderView`, and the Stats cards.

## Phase 5: Nice-to-haves (pick and choose)
- **Sharing:** a `ShareLink` for a day summary (rides, waits, spending), and CSV export of `RideLog` / `PurchaseLog` from Settings.
- **Settings cleanup:** group into Display, Wait Times, Data & Sync, and Tools. Add "Reset onboarding", "Clear telemetry" (the local telemetry store) and "Re-seed bucket list".
- **Empty states:** consistent `ContentUnavailableView` screens with a call-to-action button, for example "Add your first ride" in Ride Counter or "Browse restaurants" in Dining.
- **Walking distance:** approximate walking distance on ride cards when location is available. The `coordinate` data already exists and the map already has `showsUserLocation`.
- **Guest names:** use real names in "who's riding" labels. The `Guest` model exists; keep "Heather" as the default name.

---

## Critical files
- `ParkTrac/ContentView.swift`: tab selection, `onOpenURL`
- `ParkTrac/Models/AppState.swift`: `selectedTab`, list prefs
- `ParkTrac/Views/WaitTimes/ParkMapView.swift`: context menu, sort/filter menu, stale pill, pin accessibility
- `ParkTrac/ViewModels/WaitTimesViewModel.swift`: sort/filter logic, staleness
- `ParkTrac/Views/WaitTimes/RideDetailSheet.swift`: extract `RideActions`
- `ParkTrac/Views/Planner/DayPlannerView.swift`, `Views/Stats/StatsView.swift`: nested stack fix, swipe roles, undo
- `TrillTrackWidget/TrillTrackWidgetLiveActivity.swift`: `widgetURL`
- `ParkTrac/Info.plist`: URL scheme
- New files (`UndoToast.swift`, `RideActions.swift`) must be registered in `project.pbxproj` in all four places (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase). Use the next free `AA00…` IDs.

## Constraints
- iOS 17 APIs only: `sensoryFeedback`, `ContentUnavailableView` and `@Observable` are fine.
- No SPM dependencies.
- Any new SwiftData attribute must be optional or defaulted (CloudKit). The plan mostly avoids model changes.
- Don't rename `ParkTrac` targets or bundle IDs.

## Verification
The project has no automated tests. For each phase:
1. Build: `xcodebuild -project ParkTrac.xcodeproj -scheme ParkTrac -destination 'platform=iOS Simulator,name=iPhone 16' build`
2. Run in the simulator and walk through each change:
   - Stats → My Day shows a single nav bar with a working back button.
   - Deleting a plan item → Undo brings it back.
   - Long-press a ride → star it → the Must-Do filter shows it.
   - `xcrun simctl openurl booted thrilltrack://ride/<id>` opens the ride sheet.
   - Turn on VoiceOver (Accessibility Inspector) and check that pins read the ride name and wait.
   - Set the Dynamic Type slider to AX5 and check each tab.
   - Turn on airplane mode after a load and confirm the stale pill appears and cached rides stay visible.

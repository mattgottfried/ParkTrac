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

## Phase 1: Bugs and quick wins (small, high value)
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

## Phase 3: Navigation and deep links
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

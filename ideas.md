# ThrillTrack — Backlog

Shipped work is tracked in `docs/usability-plan.md` and the merged PRs. This file is what's next.

## Ideas

### Car locator
Remember where you parked and walk back to it at the end of the day.
- **Save spot:** a "Save Parking Spot" button (Wait Times map, My Day, or a Home Screen quick action) saves:
  - the current GPS location (`LocationService`)
  - an optional photo of the row sign
  - a note, e.g. "Zurg 112" / "Level 4, Hollywood row"
- **Find car:**
  - a car pin on the Wait Times map (`StyledMapUIView`, which already shows parking POIs)
  - distance and walking time (`WalkEstimate`)
  - a "Walk There" button that opens Apple Maps walking directions (`MKMapItem.openInMaps`)
- **Share with the party:** sync the spot through iCloud KVS (like the reviewer names) so Heather's phone sees it too. Keep one active spot per resort, cleared the next day (or kept with a history).
- **Nice-to-haves:**
  - a "Parked at…" line in My Day and the day summary
  - a reminder near park close
  - lot and row suggestions for Orlando garages and lots (TTC, Epcot, Universal garages)
  - Japan works the same way (GPS + note)

## Japan — shipped, verify on the trip (November)
Built without live data (the API can't be reached from the cloud environment). On first use, confirm:
- Tokyo and USJ resolve from `/destinations` and show parks, pins and waits (pins confirmed working).
- Tokyo `RETURN_TIME` / `PAID_RETURN_TIME` really are Priority Pass / Premier Access, and whether USJ exposes any return queue.
- Ride heights in cm match the signs at each entrance (compiled Sept 2026). Some rides also need an adult to ride along below a higher height, which isn't modelled yet.
- USJ Area Timed Entry logging, alerts and the Live Activity.
- Japan access programs are still not modelled.

## Instant alerts — shipped, verify
- Server is live at `thrilltrack-alerts.mattgottfried.deno.net`. Confirm on device: a wait alert, a reopen alert, the DAS/AAP buttons on a push, and one alert per event (no local duplicate).
- Possible follow-up: the Time Sensitive notifications entitlement, so alerts break through Focus.

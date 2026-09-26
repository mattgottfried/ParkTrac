# ThrillTrack — Backlog

Shipped work is tracked in `docs/usability-plan.md` and the merged PRs. This file is what's next.

## Ideas

### Car locator — shipped
Verify at the park: GPS accuracy in garages (top levels are fine, lower levels may need the note and photo), iCloud sync to Heather's phone, and Walk There.
Also shipped: the park-close reminder and the Home Screen quick actions (Find My Car / My Day / Wait Times).
Also shipped: lot → section → row menus for every Orlando lot and garage (names compiled Sept 2026; check the signs).
Follow-up: Tokyo / USJ lot menus.

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

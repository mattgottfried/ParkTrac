# ThrillTrack — Backlog

Shipped work is tracked in `docs/usability-plan.md` and the merged PRs. This file is what's next.

## Japan — shipped, verify on the trip
Built without live data (the API is unreachable from the cloud environment). On first use, confirm:
- Tokyo / USJ resolve from `/destinations` (slugs `tokyodisneyresort`, `universalstudiosjapan`) and show parks, pins and waits.
- Tokyo `RETURN_TIME` / `PAID_RETURN_TIME` really are Priority Pass / Premier Access (and whether USJ exposes any return queue).
- Ride names come through in English.
- Possible follow-ups: heights in cm, Japanese names, Japan access programs (currently not modelled), USJ Super Nintendo World area timed entry.

## Later
- Faster background Lightning Lane alerts need a small server (iOS background refresh is ≈hourly).
- Empty states with a call to action (Ride Counter, Dining).
- Real guest names in "who's riding" labels.

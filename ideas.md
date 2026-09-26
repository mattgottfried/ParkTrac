# ThrillTrack — Backlog

Shipped work is tracked in `docs/usability-plan.md` and the merged PRs. This file is what's next.

## Next: Japan (trip in November)
Tokyo Disney Resort (Tokyo Disneyland, Tokyo DisneySea) and Universal Studios Japan are covered by themeparks.wiki.
1. Resorts become a list, not Disney-vs-Universal: add cases for Tokyo Disney and USJ with their own destination IDs, regions and themes. **Don't rename existing `ParkGroup` raw values** — they're stored in SwiftData.
2. Show times in the park's time zone (Asia/Tokyo) rather than the phone's.
3. Tokyo Disney Premier Access (paid) and Priority Pass (free): likely the same `PAID_RETURN_TIME` / `RETURN_TIME` queues — reuse the Lightning Lane watcher + "I Booked It" with Tokyo labels. Verify against live data first.
4. USJ Express Pass as a pass type in Log Return Time.
5. Hide Orlando-only features at Japan resorts (ticket prices, AP blockouts, US-holiday crowd calendar, Orlando shop/restaurant lists); yen where prices show.
6. Nice to have: heights in cm, Japanese ride names.

## Later
- Faster background Lightning Lane alerts need a small server (iOS background refresh is ≈hourly).
- Empty states with a call to action (Ride Counter, Dining).
- Real guest names in "who's riding" labels.

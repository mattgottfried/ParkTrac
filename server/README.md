# ThrillTrack alert server

The alert server checks live wait times every minute and sends Apple push notifications. This means ThrillTrack's alerts arrive within about a minute, instead of waiting for iOS's roughly hourly background refresh.

It sends four kinds of alert:
- **Lightning Lane / Priority Pass watches**: a return time opens inside your window, or an earlier one appears later.
- **Wait alerts**: a ride's posted wait drops to your threshold. If you hold DAS or AAP at that resort, the alert carries the Book and I Booked It buttons.
- **Reopen watches**: a ride that was down or closed is operating again.
- **Area timed entry**: not sent by the server. Those reminders are scheduled locally on the phone at the time you log them.

The app stays in charge:
- Each phone uploads its own watches (`POST /v1/sync`).
- The server pushes alerts and remembers which ones it has sent.
- On the next sync, the app marks those alerts as handled.
- If the server can't be reached, the app goes back to checking on the phone.

It also keeps a **community wait history**:
- Every 10 minutes it records every operating ride's posted wait at all four resorts (Walt Disney World, Universal Orlando, Tokyo Disney Resort, Universal Studios Japan), whether or not anyone has a watch.
- It keeps 60 days of samples, one Deno KV entry per park per local hour.
- `GET /v1/history?parkId=…&weekday=1…7` (1 = Sunday) returns each ride's typical wait by local hour. That's the median for that weekday once two of those days are recorded, otherwise the median over all days. The answer is cached for 6 hours.
- The app downloads it once per park per day. It's used for hours your own phone has no history for, in the Wait Forecast, the Smart Planner and the Tip Board.

The server stores only a random ID for each install, the push token, the phone's time zone and the watches. It stores no names or accounts.

## Files

| File | What it does |
|------|--------------|
| `main.ts` | Deno Deploy entry point: runs the poll every minute and serves the HTTP API |
| `app.ts` | Sync and unregister endpoints, and the poll loop (Deno KV storage) |
| `logic.ts` | The alert rules. Pure functions that mirror the Swift rules; keep the two in step |
| `history.ts` | Community wait history: the 10-minute recorder and `GET /v1/history` |
| `apns.ts` | APNs client (ES256 provider token over HTTP/2) |
| `*_test.ts` | Tests: `deno task test` |

## One-time setup

### 1. Apple (developer.apple.com → Certificates, Identifiers & Profiles)

1. **Identifiers:** open `com.mattgottfried.parktrac`, tick **Push Notifications**, then Save.
2. **Keys → +:**
   - Name it "ThrillTrack Push".
   - Tick **Apple Push Notifications service (APNs)**.
   - Click Continue, then Register.
   - **Download the `.p8` file.** Apple only lets you download it once.
   - Note the **Key ID**.
3. **Team ID:** it's `X796Z5UW4P`, the same one shown under Membership.

### 2. Deno Deploy (console.deno.com)

1. Sign in with GitHub.
2. Create a new app (console.deno.com) from the **mattgottfried/ParkTrac** repo:
   - Framework preset None, app directory `server`, entrypoint `main.ts`, no install/build command.
   - Production deploys from the repo's default branch (`claude/vigilant-lamport-6DitA`), so every merge redeploys the server.
3. Name the app **`thrilltrack-alerts`**. It is live at **`https://thrilltrack-alerts.mattgottfried.deno.net`** (`<app>.<org>.deno.net`), which is the app's default server. A different URL can be pasted into ThrillTrack under Settings → Instant Alerts → Server.
4. If Deno Deploy asks about a database, attach a **Deno KV** database to the project.
5. Add these environment variables:

   | Name | Value |
   |------|-------|
   | `APNS_KEY_P8` | The whole contents of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` lines |
   | `APNS_KEY_ID` | The Key ID from step 1 |
   | `APNS_TEAM_ID` | `X796Z5UW4P` |
   | `APNS_TOPIC` | `com.mattgottfried.parktrac` |

6. Open `https://thrilltrack-alerts.mattgottfried.deno.net/health`. It should return `{"ok":true,...}`.

### 3. The app

In Settings → Instant Alerts, turn on **Instant Alerts** and allow notifications. The status should change to "Watching N alerts · synced just now".

- **Push environments:** builds run from Xcode use Apple's sandbox push service, while TestFlight and App Store builds use production. The app tells the server which one it is. If Settings shows "Apple rejected this phone's push token", the phone registered from the other kind of build. Opening that build again re-registers it.

## Run locally

```bash
deno task test    # unit + API tests (fake APNs, in-memory KV)
deno task start   # http://localhost:8000 (no pushes unless APNS_* are set)
```

## Costs and limits

- Each poll fetches one themeparks.wiki `/live` request per park that has an active watch, and only while watches exist.
- The history recorder makes one `/live` request per park every 10 minutes (about 10 parks), plus `/destinations` once a day. That's roughly 1,500 KV writes a day, and storage stays under a few MB.
- Two phones fit comfortably inside Deno Deploy's free tier.
- The server caps usage at 60 watches per device and 200 devices.

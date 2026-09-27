// ThrillTrack alert server — Deno Deploy entry point.
//
// Every minute: fetch live data for parks that have active watches (themeparks.wiki),
// evaluate each phone's watches, and send Apple push notifications.
// Every 10 minutes: record every ride's wait for the community history (history.ts).
// See server/README.md for setup.

import { ApnsClient } from "./apns.ts";
import { createApp, fetchLiveFromThemeParks } from "./app.ts";
import { createHistory, fetchDestinationsFromThemeParks } from "./history.ts";

const kv = await Deno.openKv();
const apns = ApnsClient.fromEnv();
if (!apns) console.warn("APNS_* env vars missing — polling runs but no pushes are sent");

const app = createApp({
  kv,
  fetchLive: fetchLiveFromThemeParks,
  send: (token, environment, push) => apns ? apns.send(token, environment, push) : Promise.resolve("failed"),
});

Deno.cron("poll watched parks", "* * * * *", async () => {
  const { parks, pushes } = await app.poll();
  if (pushes > 0) console.log(`poll: ${parks} parks, ${pushes} pushes`);
});

// Community wait history: every ride at the four resorts, every 10 minutes
const history = createHistory({
  kv,
  fetchLive: fetchLiveFromThemeParks,
  fetchDestinations: fetchDestinationsFromThemeParks,
});
Deno.cron("record wait history", "*/10 * * * *", async () => {
  const { parks, rides } = await history.record();
  if (parks > 0) console.log(`history: ${parks} parks, ${rides} rides`);
});

Deno.serve((req) => {
  const url = new URL(req.url);
  if (req.method === "GET" && url.pathname === "/v1/history") return history.handle(url);
  if (req.method === "GET" && url.pathname === "/v1/days") return history.handleDays(url);
  return app.handler(req);
});

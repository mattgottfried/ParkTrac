// ThrillTrack alert server — Deno Deploy entry point.
//
// Every minute: fetch live data for parks that have active watches (themeparks.wiki),
// evaluate each phone's watches, and send Apple push notifications.
// See server/README.md for setup.

import { ApnsClient } from "./apns.ts";
import { createApp, fetchLiveFromThemeParks } from "./app.ts";

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

Deno.serve(app.handler);

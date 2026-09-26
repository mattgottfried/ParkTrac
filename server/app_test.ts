import { assert, assertEquals } from "@std/assert";
import { createApp } from "./app.ts";
import type { LiveEntry, Push } from "./logic.ts";
import type { SendResult } from "./apns.ts";
import { payload } from "./apns.ts";

const T = 1_800_000_000;
const token = "ab".repeat(32);

function setup(opts: { result?: SendResult } = {}) {
  const sent: Push[] = [];
  let liveData: LiveEntry[] = [{ id: "r1", status: "OPERATING", queue: { STANDBY: { waitTime: 50 } } }];
  const fetched: string[] = [];
  return Deno.openKv(":memory:").then((kv) => {
    const app = createApp({
      kv,
      now: () => T,
      fetchLive: (parkId) => {
        fetched.push(parkId);
        return Promise.resolve(liveData);
      },
      send: (_t, _e, push) => {
        sent.push(push);
        return Promise.resolve(opts.result ?? "sent");
      },
    });
    return { kv, app, sent, fetched, setLive: (d: LiveEntry[]) => (liveData = d) };
  });
}

const sync = (app: ReturnType<typeof createApp>, watches: unknown[]) =>
  app.handler(
    new Request("http://x/v1/sync", {
      method: "POST",
      body: JSON.stringify({
        deviceId: "dev-1",
        token,
        environment: "production",
        timeZone: "America/New_York",
        watches,
      }),
    }),
  );

const waitWatch = {
  id: "w1",
  kind: "wait",
  rideId: "r1",
  rideName: "Slinky Dog Dash",
  parkId: "hs",
  parkName: "Hollywood Studios",
  resort: "Walt Disney World",
  expiresAt: T + 3600,
  threshold: 30,
  accessPass: null,
};

Deno.test("sync → poll → push once → state returned on next sync", async () => {
  const { kv, app, sent, fetched, setLive } = await setup();
  const res = await sync(app, [waitWatch]);
  assertEquals(res.status, 200);
  assertEquals((await res.json()).watching, 1);

  await app.poll();
  assertEquals(sent.length, 0, "50 min isn't under 30");
  assertEquals(fetched, ["hs"]);

  setLive([{ id: "r1", status: "OPERATING", queue: { STANDBY: { waitTime: 25 } } }]);
  assertEquals((await app.poll()).pushes, 1);
  assertEquals((await app.poll()).pushes, 0, "one-shot");
  assertEquals(sent[0].info.postedWait, 25);

  const again = await (await sync(app, [waitWatch])).json();
  assertEquals(again.states.w1.fired, true);
  assertEquals(again.lastPushAt, T);

  // Removing the watch forgets its state
  await sync(app, []);
  assertEquals((await kv.get(["state", "dev-1", "w1"])).value, null);
  kv.close();
});

Deno.test("no watches → no fetches", async () => {
  const { kv, app, fetched } = await setup();
  await sync(app, []);
  await app.poll();
  assertEquals(fetched.length, 0);
  kv.close();
});

Deno.test("unregistered token deletes the device", async () => {
  const { kv, app } = await setup({ result: "unregistered" });
  await sync(app, [{ ...waitWatch, threshold: 60 }]);
  await app.poll();
  assertEquals((await kv.get(["device", "dev-1"])).value, null);
  kv.close();
});

Deno.test("failed send keeps state so it retries, and reports the error", async () => {
  const { kv, app, sent } = await setup({ result: "badToken" });
  await sync(app, [{ ...waitWatch, threshold: 60 }]);
  await app.poll();
  await app.poll();
  assertEquals(sent.length, 2);
  const body = await (await sync(app, [{ ...waitWatch, threshold: 60 }])).json();
  assert(String(body.lastError).includes("rejected"));
  kv.close();
});

Deno.test("bad requests are rejected", async () => {
  const { kv, app } = await setup();
  const res = await app.handler(new Request("http://x/v1/sync", { method: "POST", body: "{" }));
  assertEquals(res.status, 400);
  await res.body?.cancel();
  const health = await app.handler(new Request("http://x/health"));
  assertEquals((await health.json()).ok, true);
  kv.close();
});

Deno.test("payload puts custom keys at the top level", () => {
  const p = payload({ title: "t", body: "b", category: "C", threadId: "th", collapseId: "c", info: { rideId: "r1" } });
  assertEquals(p.rideId, "r1");
  assertEquals((p.aps as Record<string, unknown>).category, "C");
});

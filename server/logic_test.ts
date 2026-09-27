import { assert, assertEquals } from "@std/assert";
import {
  accessReturnDelay,
  downTransition,
  type DownWatch,
  evaluate,
  type LiveEntry,
  type LLWatch,
  parseSync,
  type ReopenWatch,
  type WaitWatch,
} from "./logic.ts";

const T = Date.parse("2026-11-10T10:00:00+09:00") / 1000; // 10:00 Tokyo
const tz = "Asia/Tokyo";

const base = {
  rideId: "r1",
  rideName: "Soaring: Fantastic Flight",
  parkId: "tds",
  parkName: "Tokyo DisneySea",
  resort: "Tokyo Disney Resort",
  expiresAt: T + 86400,
};

const ll: LLWatch = {
  ...base,
  id: "w-ll",
  kind: "ll",
  passLabel: "Priority Pass",
  bookingAppName: "Tokyo Disney Resort App",
  windowStart: T + 3600,
  windowEnd: T + 4 * 3600,
};

const live = (queue: LiveEntry["queue"], status = "OPERATING"): LiveEntry => ({ id: "r1", status, queue });
const returnAt = (offset: number) => ({
  RETURN_TIME: {
    state: "AVAILABLE",
    returnStart: new Date((T + offset) * 1000).toISOString(),
    returnEnd: new Date((T + offset + 3600) * 1000).toISOString(),
  },
});

Deno.test("LL: alerts inside the window with the app's keys and category", () => {
  const r = evaluate(ll, live(returnAt(2 * 3600)), {}, T, tz);
  assert(r.push);
  assertEquals(r.push.title, "⚡ Priority Pass open: Soaring: Fantastic Flight");
  assert(r.push.body.includes("Return at 12:00 PM"), r.push.body);
  assert(r.push.body.includes("11:00 AM–2:00 PM"), r.push.body);
  assertEquals(r.push.category, "LL_WATCH_OPENING");
  assertEquals(r.push.info.returnStart, T + 2 * 3600);
  assertEquals(r.push.info.returnEnd, T + 3 * 3600);
  assertEquals(r.push.info.deepLink, "thrilltrack://ride/r1");
  assertEquals(r.state.lastNotifiedStart, T + 2 * 3600);
});

Deno.test("LL: outside window, unavailable, or not earlier → no alert", () => {
  assertEquals(evaluate(ll, live(returnAt(30 * 60)), {}, T, tz).push, undefined);
  assertEquals(evaluate(ll, live({ RETURN_TIME: { state: "FINISHED" } }), {}, T, tz).push, undefined);
  assertEquals(evaluate(ll, live(returnAt(2 * 3600)), { lastNotifiedStart: T + 2 * 3600 }, T, tz).push, undefined);
  const earlier = evaluate(ll, live(returnAt(3600 + 60)), { lastNotifiedStart: T + 2 * 3600 }, T, tz);
  assert(earlier.push?.title.startsWith("⚡ Earlier"));
});

const wait: WaitWatch = { ...base, id: "w-wait", kind: "wait", threshold: 30 };

Deno.test("wait: fires once at or under threshold while operating", () => {
  assertEquals(evaluate(wait, live({ STANDBY: { waitTime: 35 } }), {}, T, tz).push, undefined);
  assertEquals(evaluate(wait, live({ STANDBY: { waitTime: 20 } }, "DOWN"), {}, T, tz).push, undefined);
  const r = evaluate(wait, live({ STANDBY: { waitTime: 30 } }), {}, T, tz);
  assertEquals(r.push?.body, "Soaring: Fantastic Flight is now 30 min — under your 30 min alert.");
  assertEquals(r.push?.info.postedWait, 30);
  assertEquals(r.push?.category, undefined);
  assertEquals(r.state.fired, true);
  assertEquals(evaluate(wait, live({ STANDBY: { waitTime: 10 } }), r.state, T, tz).push, undefined);
});

Deno.test("wait: AAP / DAS get the booking category and return phrase", () => {
  const aap = evaluate({ ...wait, accessPass: "AAP", threshold: 60 }, live({ STANDBY: { waitTime: 20 } }), {}, T, tz);
  assertEquals(aap.push?.category, "WAIT_DROP_AAP");
  assert(aap.push?.body.endsWith("Book your AAP now to return right away."), aap.push?.body);
  const das = evaluate({ ...wait, accessPass: "DAS", threshold: 60 }, live({ STANDBY: { waitTime: 45 } }), {}, T, tz);
  assertEquals(das.push?.category, "WAIT_DROP_DAS");
  assert(das.push?.body.endsWith("return around 10:45 AM."), das.push?.body);
});

Deno.test("access pass rules match the app", () => {
  assertEquals(accessReturnDelay("AAP", 29), 0);
  assertEquals(accessReturnDelay("AAP", 30), 15);
  assertEquals(accessReturnDelay("AAP", 60), 45);
  assertEquals(accessReturnDelay("DAS", 45), 45);
});

const reopen: ReopenWatch = { ...base, id: "w-re", kind: "reopen" };

Deno.test("reopen: fires when operating again", () => {
  assertEquals(evaluate(reopen, live(null, "DOWN"), {}, T, tz).push, undefined);
  const r = evaluate(reopen, live({ STANDBY: { waitTime: 15 } }), {}, T, tz);
  assertEquals(r.push?.title, "✅ Soaring: Fantastic Flight is back up");
  assertEquals(r.push?.body, "It's operating again — posted wait 15 min.");
  assertEquals(evaluate(reopen, live({}), r.state, T, tz).push, undefined);
});

Deno.test("missing ride in live data → nothing", () => {
  assertEquals(evaluate(wait, undefined, {}, T, tz).push, undefined);
});

Deno.test("parseSync validates and drops bad or expired watches", () => {
  const token = "a".repeat(64);
  assertEquals(parseSync({ deviceId: "x", token: "nothex", environment: "production" }, T), "bad token");
  assertEquals(parseSync({ deviceId: "bad id!", token, environment: "production" }, T), "bad deviceId");
  const ok = parseSync({
    deviceId: "ABC-123",
    token: token.toUpperCase(),
    environment: "sandbox",
    timeZone: tz,
    watches: [wait, { ...wait, id: "old", expiresAt: T - 1 }, { kind: "nope" }, ll, reopen],
  }, T);
  assert(typeof ok !== "string");
  assertEquals(ok.token, token);
  assertEquals(ok.watches.map((w) => w.id), ["w-wait", "w-ll", "w-re"]);
});

const down: DownWatch = { ...base, id: "mustdo-r1", kind: "down" };

Deno.test("down: must-do goes down, then back up, then down again", () => {
  const d1 = evaluate(down, live(null, "DOWN"), {}, T, tz);
  assertEquals(d1.push?.title, "⚠️ Soaring: Fantastic Flight is down");
  assertEquals(d1.state.isDown, true);
  // Still down → quiet
  assertEquals(evaluate(down, live(null, "DOWN"), d1.state, T, tz).push, undefined);
  const up = evaluate(down, live({ STANDBY: { waitTime: 40 } }), d1.state, T, tz);
  assertEquals(up.push?.title, "✅ Soaring: Fantastic Flight is back up");
  assert(up.push?.body.includes("40 min"));
  assertEquals(up.state.isDown, false);
  assertEquals(evaluate(down, live(null, "DOWN"), up.state, T, tz).push?.collapseId, "mustdo-down-r1");
});

Deno.test("down: closing for the night resets quietly", () => {
  assertEquals(downTransition(true, "CLOSED"), { isDown: false });
  assertEquals(downTransition(false, "OPERATING"), { isDown: false });
  assertEquals(evaluate(down, live({ STANDBY: { waitTime: 5 } }), {}, T, tz).push, undefined);
});

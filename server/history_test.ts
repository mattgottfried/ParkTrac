import { assertEquals } from "@std/assert";
import {
  createHistory,
  dailyAverages,
  type HourRecord,
  localParts,
  median,
  parksFrom,
  summarize,
  waitsFrom,
} from "./history.ts";
import type { LiveEntry } from "./logic.ts";

// 2027-01-15 is a Friday
const FRI_10AM_NY = Date.parse("2027-01-15T15:00:00Z") / 1000;

Deno.test("localParts uses the park's time zone and Swift weekdays", () => {
  assertEquals(localParts(FRI_10AM_NY, "America/New_York"), { date: "2027-01-15", weekday: 6, hour: 10 });
  // Same instant is Saturday 00:00 in Tokyo
  assertEquals(localParts(FRI_10AM_NY, "Asia/Tokyo"), { date: "2027-01-16", weekday: 7, hour: 0 });
});

Deno.test("waitsFrom keeps operating attractions with a posted wait", () => {
  const entries: LiveEntry[] = [
    { id: "a", entityType: "ATTRACTION", status: "OPERATING", queue: { STANDBY: { waitTime: 45 } } },
    { id: "b", entityType: "ATTRACTION", status: "DOWN", queue: { STANDBY: { waitTime: 45 } } },
    { id: "c", entityType: "SHOW", status: "OPERATING", queue: { STANDBY: { waitTime: 10 } } },
    { id: "d", entityType: "ATTRACTION", status: "OPERATING", queue: { STANDBY: { waitTime: null } } },
  ];
  assertEquals(waitsFrom(entries), { a: 45 });
});

Deno.test("median", () => {
  assertEquals(median([]), undefined);
  assertEquals(median([30, 10, 20]), 20);
  assertEquals(median([10, 20, 30, 45]), 25);
});

const rec = (date: string, weekday: number, hour: number, waits: Record<string, number[]>): HourRecord => ({
  date,
  weekday,
  hour,
  waits,
});

Deno.test("summarize prefers the same weekday once it has two days", () => {
  const records = [
    rec("2027-01-08", 6, 10, { r: [60, 60] }), // Fridays
    rec("2027-01-15", 6, 10, { r: [70, 70] }),
    rec("2027-01-12", 3, 10, { r: [20, 20] }), // a Tuesday
  ];
  assertEquals(summarize(records, 6).rides, { r: { "10": 65 } });
});

Deno.test("summarize falls back to all days, and needs two days", () => {
  const records = [
    rec("2027-01-08", 6, 10, { r: [60] }), // one Friday only
    rec("2027-01-12", 3, 10, { r: [20] }),
    rec("2027-01-12", 3, 11, { r: [30] }), // hour 11 seen on one day only
  ];
  const s = summarize(records, 6);
  assertEquals(s.rides, { r: { "10": 40 } });
  assertEquals(s.days, 2);
});

Deno.test("parksFrom picks the four resorts", () => {
  const parks = parksFrom([
    { slug: "waltdisneyworldresort", parks: [{ id: "mk", name: "Magic Kingdom" }] },
    { slug: "someotherresort", parks: [{ id: "x", name: "X" }] },
    { slug: "universalstudiosjapan", parks: [{ id: "usj", name: "USJ" }] },
  ]);
  assertEquals(parks.map((p) => [p.id, p.timeZone]), [["mk", "America/New_York"], ["usj", "Asia/Tokyo"]]);
});

Deno.test("record + endpoint round trip", async () => {
  const kv = await Deno.openKv(":memory:");
  let t = FRI_10AM_NY;
  let wait = 40;
  const history = createHistory({
    kv,
    now: () => t,
    fetchDestinations: () =>
      Promise.resolve([{ slug: "waltdisneyworldresort", parks: [{ id: "mk", name: "Magic Kingdom" }] }]),
    fetchLive: () =>
      Promise.resolve([{
        id: "r1",
        entityType: "ATTRACTION",
        status: "OPERATING",
        queue: { STANDBY: { waitTime: wait } },
      }]),
  });
  assertEquals(await history.record(), { parks: 1, rides: 1 });
  t += 600;
  wait = 50;
  await history.record();
  // A week later, same hour
  t = FRI_10AM_NY + 7 * 86_400;
  wait = 60;
  await history.record();

  const res = await history.handle(new URL("http://x/v1/history?parkId=mk&weekday=6"));
  const body = await res.json();
  assertEquals(body.days, 2);
  assertEquals(body.rides, { r1: { "10": 50 } });

  assertEquals((await history.handle(new URL("http://x/v1/history?parkId=mk&weekday=9"))).status, 400);
  kv.close();
});

Deno.test("dailyAverages uses the middle of the day", () => {
  const records = [
    rec("2027-01-15", 6, 9, { a: [100] }), // before 10am — ignored
    rec("2027-01-15", 6, 12, { a: [40, 50], b: [30] }),
    rec("2027-01-15", 6, 18, { a: [20] }),
    rec("2027-01-16", 7, 14, { a: [61] }),
  ];
  assertEquals(dailyAverages(records), { "2027-01-15": 35, "2027-01-16": 61 });
});

Deno.test("days endpoint groups parks by resort", async () => {
  const kv = await Deno.openKv(":memory:");
  const history = createHistory({
    kv,
    now: () => FRI_10AM_NY + 2 * 3600, // noon
    fetchDestinations: () =>
      Promise.resolve([
        { slug: "waltdisneyworldresort", parks: [{ id: "mk", name: "Magic Kingdom" }] },
        { slug: "universalorlando", parks: [{ id: "usf", name: "Universal Studios Florida" }] },
      ]),
    fetchLive: () =>
      Promise.resolve([{
        id: "r1",
        entityType: "ATTRACTION",
        status: "OPERATING",
        queue: { STANDBY: { waitTime: 45 } },
      }]),
  });
  await history.record();
  const body = await (await history.handleDays(new URL("http://x/v1/days?resort=waltdisneyworldresort"))).json();
  assertEquals(body.parks, [{ id: "mk", name: "Magic Kingdom", days: { "2027-01-15": 45 } }]);
  assertEquals((await history.handleDays(new URL("http://x/v1/days?resort=nope"))).status, 400);
  kv.close();
});

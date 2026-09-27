// Community wait history: every 10 minutes record each ride's posted standby wait at all four
// resorts, and serve each ride's typical wait by hour for a weekday. The app uses it when this
// phone has no history of its own for a ride (RideProfile.waitsByHour).
//
// Storage (Deno KV):
//   ["hist", parkId, "YYYY-MM-DD", hour] → HourRecord   one per park per local hour, expires after 60 days
//   ["hist-parks"]                       → ParkList     parks of the four resorts, refreshed daily
//   ["hist-sum", parkId, weekday]        → Summary      cached answer, rebuilt every 6 hours

import type { LiveEntry } from "./logic.ts";

export const RESORTS: { slug: string; timeZone: string }[] = [
  { slug: "waltdisneyworldresort", timeZone: "America/New_York" },
  { slug: "universalorlando", timeZone: "America/New_York" },
  { slug: "tokyodisneyresort", timeZone: "Asia/Tokyo" },
  { slug: "universalstudiosjapan", timeZone: "Asia/Tokyo" },
];

export const HISTORY = {
  retentionDays: 60,
  /** A typical wait needs samples from at least this many different days */
  minDays: 2,
  summaryMaxAgeSec: 6 * 3600,
  parksMaxAgeSec: 24 * 3600,
};

export interface HistoryPark {
  id: string;
  name: string;
  timeZone: string;
  /** themeparks.wiki destination slug, e.g. "waltdisneyworldresort" */
  slug?: string;
}

/** Crowd calendar: each park's average posted wait per local day */
export interface DaysSummary {
  slug: string;
  parks: { id: string; name: string; days: Record<string, number> }[];
  builtAt: number;
}

export interface HourRecord {
  date: string;
  /** 1 = Sunday … 7 = Saturday (Swift's Calendar weekday) */
  weekday: number;
  hour: number;
  waits: Record<string, number[]>;
}

export interface Summary {
  parkId: string;
  weekday: number;
  /** Different days recorded for this park */
  days: number;
  /** ride id → local hour ("9") → typical posted wait in minutes */
  rides: Record<string, Record<string, number>>;
  builtAt: number;
}

interface Destination {
  slug?: string;
  parks?: { id?: string; name?: string }[];
}

// MARK: Pure helpers (history_test.ts)

const WEEKDAYS: Record<string, number> = { Sun: 1, Mon: 2, Tue: 3, Wed: 4, Thu: 5, Fri: 6, Sat: 7 };

/** Park-local date, weekday and hour for an epoch-seconds time. */
export function localParts(epochSec: number, timeZone: string): { date: string; weekday: number; hour: number } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
    weekday: "short",
  }).formatToParts(new Date(epochSec * 1000));
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return {
    date: `${get("year")}-${get("month")}-${get("day")}`,
    weekday: WEEKDAYS[get("weekday")] ?? 1,
    hour: Number(get("hour")) % 24,
  };
}

/** Operating attractions with a posted standby wait. */
export function waitsFrom(entries: LiveEntry[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const e of entries) {
    if (e.entityType && e.entityType !== "ATTRACTION") continue;
    if (e.status !== "OPERATING") continue;
    const w = e.queue?.STANDBY?.waitTime;
    if (typeof w === "number" && Number.isFinite(w) && w >= 0 && w <= 600) out[e.id] = Math.round(w);
  }
  return out;
}

export function median(xs: number[]): number | undefined {
  if (xs.length === 0) return undefined;
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : Math.round((s[mid - 1] + s[mid]) / 2);
}

/** Typical wait per ride per hour for `weekday`: the median over that weekday's days when at
 *  least `minDays` of them were recorded, else the median over all days. */
export function summarize(records: HourRecord[], weekday: number, minDays = HISTORY.minDays) {
  // ride → hour → { same: values/dates on this weekday, all: values/dates any day }
  type Cell = { same: number[]; sameDays: Set<string>; all: number[]; allDays: Set<string> };
  const cells = new Map<string, Map<number, Cell>>();
  const days = new Set<string>();
  for (const r of records) {
    days.add(r.date);
    for (const [rideId, waits] of Object.entries(r.waits)) {
      if (waits.length === 0) continue;
      let byHour = cells.get(rideId);
      if (!byHour) cells.set(rideId, byHour = new Map());
      let cell = byHour.get(r.hour);
      if (!cell) byHour.set(r.hour, cell = { same: [], sameDays: new Set(), all: [], allDays: new Set() });
      cell.all.push(...waits);
      cell.allDays.add(r.date);
      if (r.weekday === weekday) {
        cell.same.push(...waits);
        cell.sameDays.add(r.date);
      }
    }
  }
  const rides: Record<string, Record<string, number>> = {};
  for (const [rideId, byHour] of cells) {
    const out: Record<string, number> = {};
    for (const [hour, c] of byHour) {
      const m = c.sameDays.size >= minDays ? median(c.same) : c.allDays.size >= minDays ? median(c.all) : undefined;
      if (m !== undefined) out[String(hour)] = m;
    }
    if (Object.keys(out).length > 0) rides[rideId] = out;
  }
  return { days: days.size, rides };
}

/** Crowd level of each day: the mean of every ride sample between `fromHour` and `toHour`
 *  (local, inclusive — the busy middle of the day), rounded to one decimal. */
export function dailyAverages(records: HourRecord[], fromHour = 10, toHour = 18): Record<string, number> {
  const sums = new Map<string, { total: number; count: number }>();
  for (const r of records) {
    if (r.hour < fromHour || r.hour > toHour) continue;
    const s = sums.get(r.date) ?? { total: 0, count: 0 };
    for (const waits of Object.values(r.waits)) {
      for (const w of waits) {
        s.total += w;
        s.count++;
      }
    }
    sums.set(r.date, s);
  }
  const out: Record<string, number> = {};
  for (const [date, s] of sums) if (s.count > 0) out[date] = Math.round((s.total / s.count) * 10) / 10;
  return out;
}

/** Parks of the four resorts from themeparks.wiki GET /destinations. */
export function parksFrom(destinations: Destination[]): HistoryPark[] {
  const out: HistoryPark[] = [];
  for (const r of RESORTS) {
    const d = destinations.find((x) => x.slug === r.slug);
    for (const p of d?.parks ?? []) {
      if (typeof p.id === "string") out.push({ id: p.id, name: p.name ?? "", timeZone: r.timeZone, slug: r.slug });
    }
  }
  return out;
}

// MARK: Recorder + endpoint

export interface HistoryDeps {
  kv: Deno.Kv;
  fetchLive: (parkId: string) => Promise<LiveEntry[] | undefined>;
  fetchDestinations: () => Promise<Destination[] | undefined>;
  now?: () => number;
}

export async function fetchDestinationsFromThemeParks(): Promise<Destination[] | undefined> {
  try {
    const res = await fetch("https://api.themeparks.wiki/v1/destinations", {
      headers: { "user-agent": "ThrillTrack-history/1.0" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      await res.body?.cancel();
      return undefined;
    }
    const body = await res.json();
    return Array.isArray(body?.destinations) ? body.destinations : undefined;
  } catch {
    return undefined;
  }
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" },
  });

export function createHistory(deps: HistoryDeps) {
  const now = deps.now ?? (() => Date.now() / 1000);
  const { kv } = deps;

  async function parks(): Promise<HistoryPark[]> {
    const cached = await kv.get<{ fetchedAt: number; parks: HistoryPark[] }>(["hist-parks"]);
    // Lists cached before parks carried their resort slug are refetched
    if (
      cached.value && now() - cached.value.fetchedAt < HISTORY.parksMaxAgeSec && cached.value.parks.every((p) => p.slug)
    ) return cached.value.parks;
    const destinations = await deps.fetchDestinations();
    const list = destinations ? parksFrom(destinations) : [];
    if (list.length > 0) {
      await kv.set(["hist-parks"], { fetchedAt: now(), parks: list });
      return list;
    }
    return cached.value?.parks ?? [];
  }

  /** One pass: add every operating ride's wait to its park's current-hour record. */
  async function record(): Promise<{ parks: number; rides: number }> {
    const t = now();
    let parksRecorded = 0, rides = 0;
    await Promise.all((await parks()).map(async (park) => {
      const entries = await deps.fetchLive(park.id);
      if (!entries) return;
      const waits = waitsFrom(entries);
      const ids = Object.keys(waits);
      if (ids.length === 0) return; // closed
      const { date, weekday, hour } = localParts(t, park.timeZone);
      const key = ["hist", park.id, date, hour];
      const existing = (await kv.get<HourRecord>(key)).value;
      const rec: HourRecord = existing ?? { date, weekday, hour, waits: {} };
      for (const id of ids) (rec.waits[id] ??= []).push(waits[id]);
      await kv.set(key, rec, { expireIn: HISTORY.retentionDays * 86_400_000 });
      parksRecorded++;
      rides += ids.length;
    }));
    return { parks: parksRecorded, rides };
  }

  async function summary(parkId: string, weekday: number): Promise<Summary> {
    const key = ["hist-sum", parkId, weekday];
    const cached = (await kv.get<Summary>(key)).value;
    if (cached && now() - cached.builtAt < HISTORY.summaryMaxAgeSec) return cached;
    const cutoff = now() - HISTORY.retentionDays * 86_400;
    const records: HourRecord[] = [];
    for await (const e of kv.list<HourRecord>({ prefix: ["hist", parkId] })) {
      if (Date.parse(`${e.value.date}T12:00:00Z`) / 1000 >= cutoff) records.push(e.value);
    }
    const s = summarize(records, weekday);
    const built: Summary = { parkId, weekday, days: s.days, rides: s.rides, builtAt: now() };
    await kv.set(key, built, { expireIn: HISTORY.summaryMaxAgeSec * 1000 * 2 });
    return built;
  }

  /** Each park of a resort with its average wait per recorded day (cached 6 hours). */
  async function days(slug: string): Promise<DaysSummary> {
    const key = ["days-sum", slug];
    const cached = (await kv.get<DaysSummary>(key)).value;
    if (cached && now() - cached.builtAt < HISTORY.summaryMaxAgeSec) return cached;
    const out: DaysSummary = { slug, parks: [], builtAt: now() };
    for (const park of (await parks()).filter((p) => p.slug === slug)) {
      const records: HourRecord[] = [];
      for await (const e of kv.list<HourRecord>({ prefix: ["hist", park.id] })) records.push(e.value);
      out.parks.push({ id: park.id, name: park.name, days: dailyAverages(records) });
    }
    await kv.set(key, out, { expireIn: HISTORY.summaryMaxAgeSec * 1000 * 2 });
    return out;
  }

  /** GET /v1/days?resort=waltdisneyworldresort */
  async function handleDays(url: URL): Promise<Response> {
    const slug = url.searchParams.get("resort") ?? "";
    if (!RESORTS.some((r) => r.slug === slug)) return json({ error: "bad resort" }, 400);
    return json(await days(slug));
  }

  /** GET /v1/history?parkId=…&weekday=1…7 */
  async function handle(url: URL): Promise<Response> {
    const parkId = url.searchParams.get("parkId") ?? "";
    const weekday = Number(url.searchParams.get("weekday"));
    if (!/^[A-Za-z0-9-]{1,80}$/.test(parkId)) return json({ error: "bad parkId" }, 400);
    if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7) return json({ error: "bad weekday" }, 400);
    return json(await summary(parkId, weekday));
  }

  return { record, summary, handle, handleDays, days, parks };
}

// Shared parking lot layouts: phones send anonymous "this row is here" samples (lot, section,
// row, GPS point — nothing about the person) and download everyone's for a resort, so the car
// locator can guess the row for lots it has no map for, and which way mapped rows are numbered.
//
// Storage (Deno KV): ["pk", resortSlug, lot, section, id] → Sample, expires after 2 years,
// at most MAX_PER_SECTION per section (oldest dropped).

import { RESORTS } from "./history.ts";

export interface Sample {
  lot: string;
  section: string;
  row: string;
  latitude: number;
  longitude: number;
  at: number;
}

export const PARKING = {
  maxPerSection: 60,
  retentionMs: 2 * 365 * 86_400_000,
  /** Rough boxes around each resort — samples outside are rejected */
  bounds: {
    waltdisneyworldresort: [28.30, -81.65, 28.45, -81.45],
    universalorlando: [28.40, -81.50, 28.50, -81.40],
    tokyodisneyresort: [35.60, 139.85, 35.66, 139.91],
    universalstudiosjapan: [34.64, 135.40, 34.69, 135.46],
  } as Record<string, [number, number, number, number]>,
};

const text = (v: unknown, max: number): v is string => typeof v === "string" && v.trim().length > 0 && v.length <= max;

/** A clean sample, or an error message. */
export function parseSample(body: unknown, now: number): { slug: string; sample: Sample } | string {
  // deno-lint-ignore no-explicit-any -- untrusted JSON, checked field by field
  const b = body as any;
  if (!b || typeof b !== "object") return "body must be an object";
  if (!RESORTS.some((r) => r.slug === b.resort)) return "bad resort";
  if (!text(b.lot, 40) || typeof b.section !== "string" || b.section.length > 40 || !text(b.row, 10)) {
    return "bad lot/section/row";
  }
  const lat = b.latitude, lon = b.longitude;
  const box = PARKING.bounds[b.resort];
  if (typeof lat !== "number" || typeof lon !== "number" || !box) return "bad location";
  if (lat < box[0] || lat > box[2] || lon < box[1] || lon > box[3]) return "location outside the resort";
  return {
    slug: b.resort,
    sample: { lot: b.lot.trim(), section: b.section.trim(), row: b.row.trim(), latitude: lat, longitude: lon, at: now },
  };
}

const json = (body: unknown, status = 200, cache = false) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...(cache ? { "cache-control": "public, max-age=3600" } : {}) },
  });

export function createParking(deps: { kv: Deno.Kv; now?: () => number }) {
  const now = deps.now ?? (() => Date.now() / 1000);
  const { kv } = deps;

  async function add(req: Request): Promise<Response> {
    const body = await req.json().catch(() => null);
    const parsed = parseSample(body, now());
    if (typeof parsed === "string") return json({ error: parsed }, 400);
    const { slug, sample } = parsed;
    const prefix = ["pk", slug, sample.lot, sample.section];
    await kv.set([...prefix, `${Math.round(sample.at)}-${crypto.randomUUID()}`], sample, {
      expireIn: PARKING.retentionMs,
    });
    // Keep the newest few per section
    const keys: Deno.KvKey[] = [];
    for await (const e of kv.list({ prefix })) keys.push(e.key);
    const extra = keys.length - PARKING.maxPerSection;
    for (const key of keys.slice(0, Math.max(0, extra))) await kv.delete(key);
    return json({ ok: true });
  }

  async function list(url: URL): Promise<Response> {
    const slug = url.searchParams.get("resort") ?? "";
    if (!RESORTS.some((r) => r.slug === slug)) return json({ error: "bad resort" }, 400);
    const samples: Omit<Sample, "at">[] = [];
    for await (const e of kv.list<Sample>({ prefix: ["pk", slug] })) {
      const { lot, section, row, latitude, longitude } = e.value;
      samples.push({ lot, section, row, latitude, longitude });
    }
    return json({ samples }, 200, true);
  }

  return { add, list };
}

// HTTP API + the every-minute poll, with storage/network injected so tests can fake them.

import { evaluate, LIMITS, type LiveEntry, parseSync, type Push, type Watch, type WatchState } from "./logic.ts";
import type { SendResult } from "./apns.ts";

export interface Device {
  token: string;
  environment: "sandbox" | "production";
  timeZone: string;
  watches: Watch[];
  updatedAt: number;
  /** Last delivery problem, shown in the app's Settings */
  lastError?: string;
  lastPushAt?: number;
}

export interface Deps {
  kv: Deno.Kv;
  send: (token: string, environment: "sandbox" | "production", push: Push) => Promise<SendResult>;
  fetchLive: (parkId: string) => Promise<LiveEntry[] | undefined>;
  now?: () => number;
}

const deviceKey = (id: string) => ["device", id];
const stateKey = (id: string, watchId: string) => ["state", id, watchId];

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

export async function fetchLiveFromThemeParks(parkId: string): Promise<LiveEntry[] | undefined> {
  try {
    const res = await fetch(`https://api.themeparks.wiki/v1/entity/${encodeURIComponent(parkId)}/live`, {
      headers: { "user-agent": "ThrillTrack-alerts/1.0" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      await res.body?.cancel();
      return undefined;
    }
    const body = await res.json();
    return Array.isArray(body?.liveData) ? body.liveData : undefined;
  } catch {
    return undefined;
  }
}

export function createApp(deps: Deps) {
  const now = deps.now ?? (() => Date.now() / 1000);
  const { kv } = deps;

  async function statesFor(deviceId: string, watches: Watch[]): Promise<Record<string, WatchState>> {
    const out: Record<string, WatchState> = {};
    for (const w of watches) {
      const entry = await kv.get<WatchState>(stateKey(deviceId, w.id));
      if (entry.value) out[w.id] = entry.value;
    }
    return out;
  }

  async function deleteDevice(deviceId: string) {
    await kv.delete(deviceKey(deviceId));
    for await (const e of kv.list({ prefix: ["state", deviceId] })) await kv.delete(e.key);
  }

  async function handleSync(req: Request): Promise<Response> {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid JSON" }, 400);
    }
    const parsed = parseSync(body, now());
    if (typeof parsed === "string") return json({ error: parsed }, 400);

    const existing = await kv.get<Device>(deviceKey(parsed.deviceId));
    if (!existing.value) {
      let count = 0;
      for await (const _ of kv.list({ prefix: ["device"] })) count++;
      if (count >= LIMITS.devices) return json({ error: "server full" }, 503);
    }

    const device: Device = {
      token: parsed.token,
      environment: parsed.environment,
      timeZone: parsed.timeZone,
      watches: parsed.watches,
      updatedAt: now(),
      // A new token clears an old delivery error
      lastError: existing.value?.token === parsed.token ? existing.value?.lastError : undefined,
      lastPushAt: existing.value?.lastPushAt,
    };
    await kv.set(deviceKey(parsed.deviceId), device);

    // Forget state for watches the app no longer has
    const keep = new Set(parsed.watches.map((w) => w.id));
    for await (const e of kv.list({ prefix: ["state", parsed.deviceId] })) {
      if (!keep.has(e.key[2] as string)) await kv.delete(e.key);
    }

    return json({
      ok: true,
      watching: parsed.watches.length,
      states: await statesFor(parsed.deviceId, parsed.watches),
      lastError: device.lastError ?? null,
      lastPushAt: device.lastPushAt ?? null,
      serverTime: now(),
    });
  }

  async function handleUnregister(req: Request): Promise<Response> {
    const body = await req.json().catch(() => null) as { deviceId?: unknown } | null;
    if (typeof body?.deviceId !== "string" || !/^[A-Za-z0-9-]{1,80}$/.test(body.deviceId)) {
      return json({ error: "bad deviceId" }, 400);
    }
    await deleteDevice(body.deviceId);
    return json({ ok: true });
  }

  async function handler(req: Request): Promise<Response> {
    const url = new URL(req.url);
    if (req.method === "POST" && url.pathname === "/v1/sync") return handleSync(req);
    if (req.method === "POST" && url.pathname === "/v1/unregister") return handleUnregister(req);
    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/health")) {
      let devices = 0;
      for await (const _ of kv.list({ prefix: ["device"] })) devices++;
      return json({ ok: true, service: "ThrillTrack alerts", devices });
    }
    return json({ error: "not found" }, 404);
  }

  /** One pass: fetch each watched park once, evaluate every watch, push, save state. */
  async function poll(): Promise<{ parks: number; pushes: number }> {
    const t = now();
    const devices: { id: string; device: Device; versionstamp: string }[] = [];
    for await (const e of kv.list<Device>({ prefix: ["device"] })) {
      devices.push({ id: e.key[1] as string, device: e.value, versionstamp: e.versionstamp });
    }

    const parkIds = new Set<string>();
    for (const { device } of devices) {
      for (const w of device.watches) if (w.expiresAt > t) parkIds.add(w.parkId);
    }
    const live = new Map<string, Map<string, LiveEntry>>();
    await Promise.all([...parkIds].map(async (parkId) => {
      const entries = await deps.fetchLive(parkId);
      if (entries) live.set(parkId, new Map(entries.map((e) => [e.id, e])));
    }));

    let pushes = 0;
    for (const { id, device, versionstamp } of devices) {
      const active = device.watches.filter((w) => w.expiresAt > t);
      let lastError = device.lastError;
      let lastPushAt = device.lastPushAt;
      let unregistered = false;

      for (const watch of active) {
        const entry = live.get(watch.parkId)?.get(watch.rideId);
        if (!entry) continue;
        const key = stateKey(id, watch.id);
        const state = (await kv.get<WatchState>(key)).value ?? {};
        const result = evaluate(watch, entry, state, t, device.timeZone);
        if (!result.push) continue;

        const sent = await deps.send(device.token, device.environment, result.push);
        if (sent === "sent") {
          await kv.set(key, result.state);
          pushes++;
          lastPushAt = t;
          lastError = undefined;
        } else if (sent === "unregistered") {
          unregistered = true;
          break;
        } else {
          // Leave state alone so the next poll retries
          lastError = sent === "badToken"
            ? "Apple rejected this phone's push token (build/environment mismatch). Reopen ThrillTrack to re-register."
            : "Couldn't reach Apple's push service — will retry.";
        }
      }

      if (unregistered) {
        await deleteDevice(id);
        continue;
      }
      const changed = active.length !== device.watches.length || lastError !== device.lastError ||
        lastPushAt !== device.lastPushAt;
      if (changed) {
        // Don't clobber a sync that landed mid-poll
        await kv.atomic()
          .check({ key: deviceKey(id), versionstamp })
          .set(deviceKey(id), { ...device, watches: active, lastError, lastPushAt })
          .commit();
      }
    }
    return { parks: live.size, pushes };
  }

  return { handler, poll };
}

// Pure alert rules — mirror the app's Swift logic so a push says exactly what a local alert would.
// No I/O here; everything is unit tested in logic_test.ts.

export type Resort = "Walt Disney World" | "Universal Orlando" | "Tokyo Disney Resort" | "Universal Studios Japan";

interface WatchBase {
  id: string;
  rideId: string;
  rideName: string;
  parkId: string;
  parkName: string;
  resort: string;
  /** Epoch seconds — the server drops the watch after this */
  expiresAt: number;
}

/** Lightning Lane Multi Pass / Priority Pass: a return opens inside the window. */
export interface LLWatch extends WatchBase {
  kind: "ll";
  passLabel: string;
  bookingAppName: string;
  windowStart: number;
  windowEnd: number;
}

/** Posted standby wait drops to the threshold (one-shot). DAS/AAP holders get booking buttons. */
export interface WaitWatch extends WatchBase {
  kind: "wait";
  threshold: number;
  accessPass?: "DAS" | "AAP" | null;
}

/** A ride that's down / closed starts operating again (one-shot). */
export interface ReopenWatch extends WatchBase {
  kind: "reopen";
}

/** A Must-Do ride: alert when it goes down, and again when it's back up (repeats all day). */
export interface DownWatch extends WatchBase {
  kind: "down";
}

export type Watch = LLWatch | WaitWatch | ReopenWatch | DownWatch;

/** What the server remembers per watch between polls (returned to the app on sync). */
export interface WatchState {
  /** LL: earliest return already alerted about — only an earlier one alerts again */
  lastNotifiedStart?: number;
  /** wait / reopen: fired, the app should deactivate it */
  fired?: boolean;
  /** down: the ride is down and we've said so — the next "operating" sends "back up" */
  isDown?: boolean;
}

/** One ride from themeparks.wiki GET /entity/{parkId}/live */
export interface LiveEntry {
  id: string;
  name?: string;
  entityType?: string;
  status?: string | null;
  queue?: {
    STANDBY?: { waitTime?: number | null } | null;
    RETURN_TIME?: { state?: string | null; returnStart?: string | null; returnEnd?: string | null } | null;
  } | null;
}

export interface Push {
  title: string;
  body: string;
  category?: string;
  threadId: string;
  collapseId: string;
  /** Top-level custom keys — the app's NotificationDelegate reads these from userInfo */
  info: Record<string, string | number>;
}

export interface Evaluation {
  push?: Push;
  state: WatchState;
}

// Keys shared with NotificationKeys / DeepLink in the app — don't rename.
export const KEYS = {
  deepLink: "deepLink",
  rideId: "rideId",
  rideName: "rideName",
  parkName: "parkName",
  resort: "resort",
  postedWait: "postedWait",
  returnStart: "returnStart",
  returnEnd: "returnEnd",
  passLabel: "passLabel",
} as const;

export const CATEGORIES = {
  aapWait: "WAIT_DROP_AAP",
  dasWait: "WAIT_DROP_DAS",
  llWatch: "LL_WATCH_OPENING",
} as const;

const rideLink = (rideId: string) => `thrilltrack://ride/${encodeURIComponent(rideId)}`;

export function parseDate(s: string | null | undefined): number | undefined {
  if (!s) return undefined;
  const ms = Date.parse(s);
  return Number.isNaN(ms) ? undefined : ms / 1000;
}

/** "2:35 PM" in the phone's time zone (what the app's .formatted(time: .shortened) shows). */
export function formatTime(epochSeconds: number, timeZone: string): string {
  try {
    return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone })
      .format(new Date(epochSeconds * 1000));
  } catch {
    return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: "UTC" })
      .format(new Date(epochSeconds * 1000));
  }
}

/** Same as AccessPass.returnDelayMinutes: AAP < 30 → 0, else wait − 15; DAS = wait. */
export function accessReturnDelay(pass: "DAS" | "AAP", postedWait: number): number {
  const wait = Math.max(0, postedWait);
  if (pass === "AAP") return wait < 30 ? 0 : wait - 15;
  return wait;
}

export function isOperating(entry: LiveEntry): boolean {
  return entry.status === "OPERATING";
}

/** Same rule as LightningLaneWatchService.alertStart. */
export function llAlertStart(watch: LLWatch, entry: LiveEntry, state: WatchState): number | undefined {
  const q = entry.queue?.RETURN_TIME;
  if (!q || q.state !== "AVAILABLE") return undefined;
  const start = parseDate(q.returnStart);
  if (start === undefined) return undefined;
  if (start < watch.windowStart || start > watch.windowEnd) return undefined;
  if (state.lastNotifiedStart !== undefined && start >= state.lastNotifiedStart) return undefined;
  return start;
}

export function evaluate(
  watch: Watch,
  entry: LiveEntry | undefined,
  state: WatchState,
  now: number,
  timeZone: string,
): Evaluation {
  if (!entry) return { state };

  switch (watch.kind) {
    case "ll": {
      const start = llAlertStart(watch, entry, state);
      if (start === undefined) return { state };
      const end = parseDate(entry.queue?.RETURN_TIME?.returnEnd);
      const time = formatTime(start, timeZone);
      const previous = state.lastNotifiedStart;
      const window = `${formatTime(watch.windowStart, timeZone)}–${formatTime(watch.windowEnd, timeZone)}`;
      const info: Record<string, string | number> = {
        [KEYS.deepLink]: rideLink(watch.rideId),
        [KEYS.rideId]: watch.rideId,
        [KEYS.rideName]: watch.rideName,
        [KEYS.parkName]: watch.parkName,
        [KEYS.resort]: watch.resort,
        [KEYS.passLabel]: watch.passLabel,
        [KEYS.returnStart]: start,
      };
      if (end !== undefined) info[KEYS.returnEnd] = end;
      return {
        state: { ...state, lastNotifiedStart: start },
        push: {
          title: previous !== undefined
            ? `⚡ Earlier ${watch.passLabel}: ${watch.rideName}`
            : `⚡ ${watch.passLabel} open: ${watch.rideName}`,
          body: previous !== undefined
            ? `Return at ${time} is open now (earlier than ${
              formatTime(previous, timeZone)
            }). Book it in the ${watch.bookingAppName}.`
            : `Return at ${time} is open now, inside your ${window} window. Book it in the ${watch.bookingAppName}.`,
          category: CATEGORIES.llWatch,
          threadId: `ll-watch-${watch.rideId}`,
          collapseId: `llwatch-${watch.rideId}-${start}`,
          info,
        },
      };
    }

    case "wait": {
      if (state.fired) return { state };
      const wait = entry.queue?.STANDBY?.waitTime;
      if (!isOperating(entry) || typeof wait !== "number" || wait > watch.threshold) return { state };
      let body = `${watch.rideName} is now ${wait} min — under your ${watch.threshold} min alert.`;
      let category: string | undefined;
      if (watch.accessPass) {
        const delay = accessReturnDelay(watch.accessPass, wait);
        const phrase = delay === 0 ? "right away" : `around ${formatTime(now + delay * 60, timeZone)}`;
        body += ` Book your ${watch.accessPass} now to return ${phrase}.`;
        category = watch.accessPass === "AAP" ? CATEGORIES.aapWait : CATEGORIES.dasWait;
      }
      return {
        state: { ...state, fired: true },
        push: {
          title: "⏱ Wait time dropped!",
          body,
          category,
          threadId: `wait-${watch.rideId}`,
          collapseId: `alert-${watch.rideId}`,
          info: {
            [KEYS.deepLink]: rideLink(watch.rideId),
            [KEYS.rideId]: watch.rideId,
            [KEYS.rideName]: watch.rideName,
            [KEYS.parkName]: watch.parkName,
            [KEYS.resort]: watch.resort,
            [KEYS.postedWait]: wait,
          },
        },
      };
    }

    case "down":
      return evaluateDown(watch, entry, state);

    case "reopen": {
      if (state.fired || !isOperating(entry)) return { state };
      const wait = entry.queue?.STANDBY?.waitTime;
      return {
        state: { ...state, fired: true },
        push: {
          title: `✅ ${watch.rideName} is back up`,
          body: typeof wait === "number" ? `It's operating again — posted wait ${wait} min.` : "It's operating again.",
          threadId: `reopen-${watch.rideId}`,
          collapseId: `reopen-${watch.rideId}`,
          info: {
            [KEYS.deepLink]: rideLink(watch.rideId),
            [KEYS.rideId]: watch.rideId,
            [KEYS.rideName]: watch.rideName,
            [KEYS.parkName]: watch.parkName,
            [KEYS.resort]: watch.resort,
          },
        },
      };
    }
  }
}

/** Same rule as the app's MustDoDown.transition. CLOSED / refurbishment quietly resets. */
export function downTransition(isDown: boolean, status: string | null | undefined): {
  event?: "down" | "backUp";
  isDown: boolean;
} {
  if (status === "DOWN") return isDown ? { isDown: true } : { event: "down", isDown: true };
  if (status === "OPERATING") return isDown ? { event: "backUp", isDown: false } : { isDown: false };
  return { isDown: false };
}

export function evaluateDown(watch: DownWatch, entry: LiveEntry, state: WatchState): Evaluation {
  const t = downTransition(state.isDown ?? false, entry.status);
  const next: WatchState = { ...state, isDown: t.isDown };
  if (!t.event) return { state: next };
  const info = {
    [KEYS.deepLink]: rideLink(watch.rideId),
    [KEYS.rideId]: watch.rideId,
    [KEYS.rideName]: watch.rideName,
    [KEYS.parkName]: watch.parkName,
    [KEYS.resort]: watch.resort,
  };
  if (t.event === "down") {
    return {
      state: next,
      push: {
        title: `⚠️ ${watch.rideName} is down`,
        body: "One of your Must-Dos just stopped running. ThrillTrack will tell you when it's back up.",
        threadId: `mustdo-${watch.rideId}`,
        collapseId: `mustdo-down-${watch.rideId}`,
        info,
      },
    };
  }
  const wait = entry.queue?.STANDBY?.waitTime;
  return {
    state: next,
    push: {
      title: `✅ ${watch.rideName} is back up`,
      body: typeof wait === "number"
        ? `Your Must-Do is running again — posted wait ${wait} min.`
        : "Your Must-Do is running again.",
      threadId: `mustdo-${watch.rideId}`,
      collapseId: `mustdo-up-${watch.rideId}`,
      info,
    },
  };
}

// MARK: - Sync validation

export interface SyncRequest {
  deviceId: string;
  token: string;
  environment: "sandbox" | "production";
  timeZone: string;
  watches: Watch[];
}

export const LIMITS = { watchesPerDevice: 60, devices: 200 };

const str = (v: unknown, max = 200): v is string => typeof v === "string" && v.length > 0 && v.length <= max;
const num = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);

// deno-lint-ignore no-explicit-any -- untrusted JSON, checked field by field
function validWatch(w: any): w is Watch {
  if (!w || typeof w !== "object") return false;
  if (!str(w.id, 80) || !str(w.rideId) || !str(w.rideName) || !str(w.parkId) || !num(w.expiresAt)) return false;
  if (typeof w.parkName !== "string" || typeof w.resort !== "string") return false;
  switch (w.kind) {
    case "ll":
      return str(w.passLabel, 60) && str(w.bookingAppName, 80) && num(w.windowStart) && num(w.windowEnd);
    case "wait":
      return num(w.threshold) && (w.accessPass == null || w.accessPass === "DAS" || w.accessPass === "AAP");
    case "reopen":
    case "down":
      return true;
    default:
      return false;
  }
}

/** Returns a clean request, or an error message. Unknown/invalid watches are dropped, not fatal. */
export function parseSync(body: unknown, now: number): SyncRequest | string {
  // deno-lint-ignore no-explicit-any -- untrusted JSON, checked field by field
  const b = body as any;
  if (!b || typeof b !== "object") return "body must be an object";
  if (!str(b.deviceId, 80) || !/^[A-Za-z0-9-]+$/.test(b.deviceId)) return "bad deviceId";
  if (!str(b.token, 200) || !/^[0-9a-fA-F]{32,200}$/.test(b.token)) return "bad token";
  if (b.environment !== "sandbox" && b.environment !== "production") return "bad environment";
  const timeZone = str(b.timeZone, 64) ? b.timeZone : "UTC";
  const watches = (Array.isArray(b.watches) ? b.watches : [])
    .filter(validWatch)
    .filter((w: Watch) => w.expiresAt > now)
    .slice(0, LIMITS.watchesPerDevice);
  return { deviceId: b.deviceId, token: b.token.toLowerCase(), environment: b.environment, timeZone, watches };
}

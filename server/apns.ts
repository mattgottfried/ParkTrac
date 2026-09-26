// Apple Push Notification service client (token-based auth, HTTP/2 via Deno's fetch).
//
// Env: APNS_KEY_P8 (contents of the .p8 file), APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC (bundle id).

import type { Push } from "./logic.ts";

export interface ApnsConfig {
  keyP8: string;
  keyId: string;
  teamId: string;
  topic: string;
}

/** unregistered: app deleted / token revoked. badToken: usually a sandbox token sent to production or vice versa. */
export type SendResult = "sent" | "unregistered" | "badToken" | "failed";

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJson = (obj: unknown) => b64url(new TextEncoder().encode(JSON.stringify(obj)));

function pemToPkcs8(pem: string): Uint8Array<ArrayBuffer> {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** The APNs payload the app receives. Custom keys sit at the top level (userInfo). */
export function payload(push: Push): Record<string, unknown> {
  const aps: Record<string, unknown> = {
    alert: { title: push.title, body: push.body },
    sound: "default",
    "thread-id": push.threadId,
    // Time Sensitive breaks through Focus; needs the entitlement, harmless without it
    "interruption-level": "time-sensitive",
  };
  if (push.category) aps.category = push.category;
  return { aps, ...push.info };
}

export class ApnsClient {
  private key?: CryptoKey;
  private jwt?: { token: string; issuedAt: number };

  constructor(private config: ApnsConfig) {}

  static fromEnv(): ApnsClient | undefined {
    const keyP8 = Deno.env.get("APNS_KEY_P8");
    const keyId = Deno.env.get("APNS_KEY_ID");
    const teamId = Deno.env.get("APNS_TEAM_ID");
    const topic = Deno.env.get("APNS_TOPIC");
    if (!keyP8 || !keyId || !teamId || !topic) return undefined;
    return new ApnsClient({ keyP8, keyId, teamId, topic });
  }

  /** Provider token, reused for 50 minutes (Apple rejects refreshing more than every 20). */
  private async token(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.jwt && now - this.jwt.issuedAt < 50 * 60) return this.jwt.token;
    this.key ??= await crypto.subtle.importKey(
      "pkcs8",
      pemToPkcs8(this.config.keyP8),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
    const unsigned = `${b64urlJson({ alg: "ES256", kid: this.config.keyId })}.${
      b64urlJson({ iss: this.config.teamId, iat: now })
    }`;
    // WebCrypto ECDSA signatures are already raw r||s, which is what JWS wants
    const sig = new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        this.key,
        new TextEncoder().encode(unsigned),
      ),
    );
    this.jwt = { token: `${unsigned}.${b64url(sig)}`, issuedAt: now };
    return this.jwt.token;
  }

  async send(deviceToken: string, environment: "sandbox" | "production", push: Push): Promise<SendResult> {
    const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    try {
      const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${await this.token()}`,
          "apns-topic": this.config.topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-collapse-id": push.collapseId.slice(0, 64),
        },
        body: JSON.stringify(payload(push)),
      });
      if (res.ok) {
        await res.body?.cancel();
        return "sent";
      }
      const text = await res.text();
      // 410 = token no longer valid (app deleted / notifications reset)
      if (res.status === 410 || text.includes("Unregistered")) return "unregistered";
      if (text.includes("BadDeviceToken")) return "badToken";
      if (text.includes("ExpiredProviderToken")) this.jwt = undefined;
      console.error(`APNs ${res.status}: ${text}`);
      return "failed";
    } catch (err) {
      console.error("APNs request failed", err);
      return "failed";
    }
  }
}

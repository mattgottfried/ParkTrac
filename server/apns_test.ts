import { assert, assertEquals } from "@std/assert";
import { ApnsClient } from "./apns.ts";

const b64urlDecode = (s: string) =>
  Uint8Array.from(
    atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - s.length % 4) % 4)),
    (c) => c.charCodeAt(0),
  );

Deno.test("signs a valid ES256 provider token and posts to the right host", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
  const client = new ApnsClient({ keyP8: pem, keyId: "KEY123", teamId: "TEAM456", topic: "com.example.app" });

  const realFetch = globalThis.fetch;
  const seen: { url: string; headers: Headers; body: string }[] = [];
  globalThis.fetch = (input, init) => {
    seen.push({ url: String(input), headers: new Headers(init?.headers), body: String(init?.body) });
    return Promise.resolve(new Response(null, { status: 200 }));
  };
  try {
    const push = { title: "t", body: "b", threadId: "x", collapseId: "c", info: { rideId: "r" } };
    assertEquals(await client.send("ab".repeat(32), "sandbox", push), "sent");
    assertEquals(await client.send("ab".repeat(32), "production", push), "sent");
  } finally {
    globalThis.fetch = realFetch;
  }

  assert(seen[0].url.startsWith("https://api.sandbox.push.apple.com/3/device/"));
  assert(seen[1].url.startsWith("https://api.push.apple.com/3/device/"));
  assertEquals(seen[0].headers.get("apns-topic"), "com.example.app");
  const jwt = seen[0].headers.get("authorization")!.replace("bearer ", "");
  assertEquals(jwt, seen[1].headers.get("authorization")!.replace("bearer ", ""), "token reused");
  const [h, p, s] = jwt.split(".");
  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(h))), { alg: "ES256", kid: "KEY123" });
  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(p))).iss, "TEAM456");
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    b64urlDecode(s),
    new TextEncoder().encode(`${h}.${p}`),
  );
  assert(ok, "signature verifies");
});

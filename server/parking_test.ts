import { assertEquals } from "@std/assert";
import { createParking, PARKING, parseSample } from "./parking.ts";

const T = 1_800_000_000;
const good = {
  resort: "waltdisneyworldresort",
  lot: "EPCOT",
  section: "Gamora",
  row: "812",
  latitude: 28.3792,
  longitude: -81.5433,
};

Deno.test("parseSample validates", () => {
  assertEquals(typeof parseSample(good, T), "object");
  assertEquals(parseSample({ ...good, resort: "nope" }, T), "bad resort");
  assertEquals(parseSample({ ...good, row: "" }, T), "bad lot/section/row");
  assertEquals(parseSample({ ...good, latitude: 40 }, T), "location outside the resort");
  assertEquals(typeof parseSample({ ...good, section: "" }, T), "object", "lots without sections");
});

Deno.test("add + list, capped per section", async () => {
  const kv = await Deno.openKv(":memory:");
  let t = T;
  const parking = createParking({ kv, now: () => t++ });
  for (let i = 0; i < PARKING.maxPerSection + 5; i++) {
    const res = await parking.add(
      new Request("http://x/v1/parking/sample", {
        method: "POST",
        body: JSON.stringify({ ...good, row: String(801 + (i % 20)) }),
      }),
    );
    assertEquals(res.status, 200);
  }
  const body = await (await parking.list(new URL("http://x/v1/parking/samples?resort=waltdisneyworldresort"))).json();
  assertEquals(body.samples.length, PARKING.maxPerSection);
  assertEquals(body.samples[0].section, "Gamora");
  assertEquals((await parking.list(new URL("http://x/v1/parking/samples?resort=x"))).status, 400);
  kv.close();
});

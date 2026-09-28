import { test } from "node:test";
import assert from "node:assert/strict";
import { HttpRequest, InvocationContext } from "@azure/functions";
import type { CounterStore } from "../src/counter";
import { createVisitsHandler } from "../src/visitsHandler";

const store: CounterStore = {
  increment: async () => 7,
  get: async () => 6,
};

const request = (method: string, query = "") =>
  new HttpRequest({ method, url: `https://example.test/api/visits${query}` });

test("POST returns the new count as JSON and is never cached", async () => {
  const res = await createVisitsHandler(() => store)(request("POST"), new InvocationContext());
  assert.equal(res.status, 200);
  assert.deepEqual(res.jsonBody, { count: 7 });
  assert.deepEqual(res.headers, { "Cache-Control": "no-store" });
});

test("the counter id comes from the query string", async () => {
  const res = await createVisitsHandler(() => store)(request("GET", "?id=nope"), new InvocationContext());
  assert.equal(res.status, 400);
});

test("a store or configuration failure becomes a 503 without leaking details", async () => {
  const failing = createVisitsHandler(() => {
    throw new Error("COSMOS_ENDPOINT is not set");
  });
  const res = await failing(request("GET"), new InvocationContext());
  assert.equal(res.status, 503);
  assert.deepEqual(res.jsonBody, { error: "Counter unavailable" });
});

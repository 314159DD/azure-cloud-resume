import { test } from "node:test";
import assert from "node:assert/strict";
import { handleVisits, type CounterStore } from "../src/counter";

class FakeStore implements CounterStore {
  readonly counts = new Map<string, number>();
  async increment(id: string): Promise<number> {
    const next = (this.counts.get(id) ?? 0) + 1;
    this.counts.set(id, next);
    return next;
  }
  async get(id: string): Promise<number> {
    return this.counts.get(id) ?? 0;
  }
}

test("GET returns 0 before the first visit", async () => {
  assert.deepEqual(await handleVisits("GET", new FakeStore()), { status: 200, body: { count: 0 } });
});

test("POST increments, GET only reads", async () => {
  const store = new FakeStore();
  await handleVisits("POST", store);
  assert.deepEqual(await handleVisits("post", store), { status: 200, body: { count: 2 } });
  assert.deepEqual(await handleVisits("GET", store), { status: 200, body: { count: 2 } });
});

test("the smoke-test counter is separate from the public one", async () => {
  const store = new FakeStore();
  await handleVisits("POST", store, "smoke");
  assert.deepEqual(await handleVisits("GET", store), { status: 200, body: { count: 0 } });
  assert.deepEqual(await handleVisits("GET", store, "smoke"), { status: 200, body: { count: 1 } });
});

test("unknown counters are rejected without touching the store", async () => {
  const store = new FakeStore();
  assert.deepEqual(await handleVisits("POST", store, "anything"), { status: 400, body: { error: "Unknown counter" } });
  assert.equal(store.counts.size, 0);
});

test("other methods are rejected without touching the store", async () => {
  const store = new FakeStore();
  assert.equal((await handleVisits("DELETE", store)).status, 405);
  assert.equal(store.counts.size, 0);
});

import { test } from "node:test";
import assert from "node:assert/strict";
import type { Container } from "@azure/cosmos";
import { CosmosCounterStore } from "../src/cosmosStore";

const cosmosError = (code: number) => Object.assign(new Error(`cosmos ${String(code)}`), { code });

/** Minimal in-memory stand-in for the parts of a Cosmos Container the store uses. */
function fakeContainer(opts: { createConflictsOnce?: boolean } = {}) {
  const docs = new Map<string, { id: string; count: number }>();
  let conflictPending = opts.createConflictsOnce ?? false;
  const calls: string[] = [];
  const container = {
    item: (id: string) => ({
      patch: async (ops: { op: string; value: number }[]) => {
        calls.push("patch");
        const doc = docs.get(id);
        if (!doc) throw cosmosError(404);
        doc.count += ops[0].value;
        return { resource: { ...doc } };
      },
      read: async () => {
        const doc = docs.get(id);
        if (!doc) throw cosmosError(404);
        return { resource: { ...doc } };
      },
    }),
    items: {
      create: async (doc: { id: string; count: number }) => {
        calls.push("create");
        if (conflictPending) {
          // Simulate a concurrent request that created the document first.
          conflictPending = false;
          docs.set(doc.id, { id: doc.id, count: 1 });
          throw cosmosError(409);
        }
        docs.set(doc.id, { ...doc });
        return { resource: doc };
      },
    },
  };
  return { container: container as unknown as Container, docs, calls };
}

test("first visit creates the document, later visits patch it", async () => {
  const { container, calls } = fakeContainer();
  const store = new CosmosCounterStore(container);
  assert.equal(await store.increment("resume"), 1);
  assert.equal(await store.increment("resume"), 2);
  assert.deepEqual(calls, ["patch", "create", "patch"]);
});

test("a create race (409) falls back to the atomic increment", async () => {
  const { container } = fakeContainer({ createConflictsOnce: true });
  const store = new CosmosCounterStore(container);
  // The concurrent writer counted 1, this request must count on top of it.
  assert.equal(await store.increment("resume"), 2);
});

test("get returns 0 for a missing counter", async () => {
  const { container } = fakeContainer();
  assert.equal(await new CosmosCounterStore(container).get("resume"), 0);
});

test("unexpected errors are not swallowed", async () => {
  const container = {
    item: () => ({ patch: async () => { throw cosmosError(403); } }),
  } as unknown as Container;
  await assert.rejects(new CosmosCounterStore(container).increment("resume"), /cosmos 403/);
});

test("fromEnv fails fast without an endpoint", () => {
  assert.throws(() => CosmosCounterStore.fromEnv({}), /COSMOS_ENDPOINT/);
});

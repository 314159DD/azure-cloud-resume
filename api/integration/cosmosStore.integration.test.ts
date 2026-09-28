// Integration test of the Cosmos DB adapter against the Linux Cosmos DB emulator (CI service container).
// It exercises what the unit tests can only fake: the real patch "incr" operation, the 404 on a missing
// document and the 409 create race, all through the actual SDK and wire protocol.
//
// Run: COSMOS_EMULATOR_ENDPOINT=http://localhost:8081 npm run test:integration
// Skipped when the endpoint is not set, so `npm test` stays fast and self-contained.
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { CosmosClient, type Container, type Database } from "@azure/cosmos";
import { CosmosCounterStore } from "../src/cosmosStore";

const endpoint = process.env.COSMOS_EMULATOR_ENDPOINT;
// The emulator's well-known, publicly documented key. It only works against the local emulator.
const EMULATOR_KEY = "C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==";
const skip = endpoint ? false : "COSMOS_EMULATOR_ENDPOINT not set";

let database: Database | undefined;
let container: Container;

before(async () => {
  if (!endpoint) return;
  const client = new CosmosClient({ endpoint, key: EMULATOR_KEY });
  const created = await client.databases.createIfNotExists({ id: `it-${randomUUID()}` });
  database = created.database;
  ({ container } = await created.database.containers.createIfNotExists({ id: "counters", partitionKey: { paths: ["/id"] } }));
});

after(async () => {
  await database?.delete();
});

test("first visit creates the counter, later visits increment it", { skip }, async () => {
  const store = new CosmosCounterStore(container);
  assert.equal(await store.get("resume"), 0);
  assert.equal(await store.increment("resume"), 1);
  assert.equal(await store.increment("resume"), 2);
  assert.equal(await store.get("resume"), 2);
});

test("concurrent increments are atomic, including the create race on a new counter", { skip }, async () => {
  const store = new CosmosCounterStore(container);
  const results = await Promise.all(Array.from({ length: 25 }, () => store.increment("race")));
  assert.equal(new Set(results).size, 25, `duplicate counts returned: ${results.join(",")}`);
  assert.deepEqual([...results].sort((a, b) => a - b), Array.from({ length: 25 }, (_, i) => i + 1));
  assert.equal(await store.get("race"), 25);
});

import { app } from "@azure/functions";
import type { CounterStore } from "../counter";
import { CosmosCounterStore } from "../cosmosStore";
import { createVisitsHandler } from "../visitsHandler";

// Created once per instance, not per invocation: the client keeps connections and a token cache.
let store: CounterStore | undefined;

app.http("visits", {
  methods: ["GET", "POST"],
  authLevel: "anonymous",
  handler: createVisitsHandler(() => (store ??= CosmosCounterStore.fromEnv())),
});

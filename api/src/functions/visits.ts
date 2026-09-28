import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { handleVisits, type CounterStore } from "../counter";
import { CosmosCounterStore } from "../cosmosStore";

// Created once per instance, not per invocation: the client keeps connections and a token cache.
let store: CounterStore | undefined;

export async function visits(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  store ??= CosmosCounterStore.fromEnv();
  const headers = { "Cache-Control": "no-store" };
  try {
    const result = await handleVisits(request.method, store);
    return { status: result.status, jsonBody: result.body, headers };
  } catch (e) {
    context.error("Counter operation failed", e);
    return { status: 503, jsonBody: { error: "Counter unavailable" }, headers };
  }
}

app.http("visits", {
  methods: ["GET", "POST"],
  authLevel: "anonymous",
  handler: visits,
});

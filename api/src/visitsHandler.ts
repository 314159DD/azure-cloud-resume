import type { HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { handleVisits, type CounterStore } from "./counter";

const headers = { "Cache-Control": "no-store" };

/**
 * HTTP adapter for the counter. The store comes from a factory so tests can inject a fake and the
 * production wiring can create the Cosmos client lazily (a configuration error then becomes a 503
 * response instead of a failed function load).
 */
export function createVisitsHandler(getStore: () => CounterStore) {
  return async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    try {
      const result = await handleVisits(request.method, getStore(), request.query.get("id"));
      return { status: result.status, jsonBody: result.body, headers };
    } catch (e) {
      context.error("Counter operation failed", e);
      return { status: 503, jsonBody: { error: "Counter unavailable" }, headers };
    }
  };
}

// Domain logic of the visitor counter. No Azure dependency, so it stays unit-testable:
// persistence sits behind the CounterStore port (Cosmos DB in production, a fake in tests).

export interface CounterStore {
  /** Atomically increments the counter by one and returns the new value. */
  increment(id: string): Promise<number>;
  /** Returns the current value, or 0 if the counter does not exist yet. */
  get(id: string): Promise<number>;
}

export type VisitsBody = { count: number } | { error: string };

export interface VisitsResult {
  status: number;
  body: VisitsBody;
}

export const COUNTER_ID = "resume";

export async function handleVisits(method: string, store: CounterStore): Promise<VisitsResult> {
  switch (method.toUpperCase()) {
    case "POST":
      return { status: 200, body: { count: await store.increment(COUNTER_ID) } };
    case "GET":
      return { status: 200, body: { count: await store.get(COUNTER_ID) } };
    default:
      return { status: 405, body: { error: "Method not allowed" } };
  }
}

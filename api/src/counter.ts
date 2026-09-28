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

/** The public counter shown on the site. */
export const DEFAULT_COUNTER = "resume";

/**
 * Counters a caller may address. "smoke" is used by the post-deploy smoke test so that verifying
 * the live system does not change the public number. Anything else is rejected, which keeps callers
 * from creating arbitrary documents.
 */
export const COUNTERS: readonly string[] = [DEFAULT_COUNTER, "smoke"];

export async function handleVisits(
  method: string,
  store: CounterStore,
  counterId: string | null = null,
): Promise<VisitsResult> {
  const id = counterId ?? DEFAULT_COUNTER;
  if (!COUNTERS.includes(id)) {
    return { status: 400, body: { error: "Unknown counter" } };
  }
  switch (method.toUpperCase()) {
    case "POST":
      return { status: 200, body: { count: await store.increment(id) } };
    case "GET":
      return { status: 200, body: { count: await store.get(id) } };
    default:
      return { status: 405, body: { error: "Method not allowed" } };
  }
}

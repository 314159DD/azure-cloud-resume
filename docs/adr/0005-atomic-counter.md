# 5. Atomic server-side increment for the counter

- Status: accepted
- Date: 2026-09-28

## Context

A counter implemented as read, add one, write loses updates under concurrency: two requests read 41 and
both write 42.

## Decision

Use the Cosmos DB partial document update (`patch` with `incr`), which the service applies atomically.
The first visit creates the document; a concurrent create (HTTP 409) falls back to the increment.

## Consequences

- No lost updates: 20 concurrent POSTs against the deployed API increase the counter by exactly 20. The
  post-deploy smoke test runs this against a separate `smoke` counter, so verification never changes the public
  number and a real visitor during the run cannot make it fail. The API accepts only the two known counter ids.
- Domain logic stays behind a `CounterStore` port and is unit-tested without Azure; the adapter's edge cases
  (first visit, create race, unexpected errors) are tested against an in-memory fake.

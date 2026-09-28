# 4. Cost guardrails that stop, not just warn

- Status: accepted
- Date: 2026-09-28

## Context

Budgets and alerts only notify, and cost data lags by hours. A public, anonymous endpoint on a usage-billed
plan can be flooded. The question is not "will we be notified" but "what stops the spend".

## Decision

Hard limits where the platform offers them, automation where it does not:

| Resource | Guardrail | Type |
|---|---|---|
| Cosmos DB | free tier + `totalThroughputLimit: 1000` (excess gets HTTP 429) | hard |
| Log Analytics | 0.1 GB daily ingestion cap | hard |
| Static Web Apps | Free plan (cannot incur charges) | hard |
| Function compute | 1 instance, 10 concurrent requests | hard |
| Function executions | metric alert (1500 executions / 5 min) -> action group -> Logic App stops the app | automated |
| Everything | monthly budget: e-mail at 20 %, forecast alert, kill switch at 100 % | automated, lagging |

The Logic App uses its own managed identity with **Website Contributor on the function app only**.

## Consequences

- Worst case is bounded to roughly minutes of flood traffic before the app stops itself.
- A stopped app needs a human: `az functionapp start`. That is intentional.
- The threshold must stay well below the throughput the scale caps allow. A first threshold of 3000 never fired
  during a flood test because throttling kept the metric just under it; lowered to 1500 and re-tested.

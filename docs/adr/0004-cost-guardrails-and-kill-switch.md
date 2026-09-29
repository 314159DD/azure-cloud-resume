# 4. Cost guardrails with an automatic stop

- Status: accepted
- Date: 2026-09-28

## Context

Budgets and alerts only send notifications, and Azure cost data arrives hours late. The API is public,
anonymous and billed per use, so a flood of requests turns directly into cost. Something has to stop the spending
without waiting for a person to read an e-mail.

## Decision

Use hard limits where the platform has them and automation where it does not:

| Resource | Limit | Type |
|---|---|---|
| Cosmos DB | free tier and `totalThroughputLimit: 1000`; excess requests get HTTP 429 | hard |
| Log Analytics | 0.1 GB daily ingestion cap | hard |
| Static Web Apps | Free plan, which cannot incur charges | hard |
| Function compute | 1 instance, 10 concurrent requests | hard |
| Function executions | two metric alerts, 1,500 executions in 5 minutes (burst) and 20,000 in 24 hours (sustained), trigger an action group whose Logic App stops the app | automated |
| All resources | monthly budget: e-mail at 20 %, forecast alert, kill switch at 100 % | automated, lags by hours |

The Logic App runs as its own managed identity. On the function app it holds a custom role that allows
`sites/read`, `sites/stop/action` and `sites/start/action` and nothing else; the built-in Website Contributor role
would also let it change settings and deploy code. The bootstrap script creates the role, because the pipeline's
Contributor role cannot create role definitions.

## Consequences

- A burst runs for a few minutes at most before the app stops itself. Steady traffic just under the burst
  threshold (up to about 5 requests per second) is caught by the 24-hour alert within a day, long before it
  would cost more than a few euros; the budget is the backstop behind both.
- The kill switch doubles as a denial-of-service lever: about 1,500 requests in 5 minutes take the counter
  offline. Here the availability of a visit count is worth less than an unbounded bill. A service that must stay
  up would rate-limit per client in front of the API (Azure Front Door with a WAF rule, a paid option).
- Someone has to restart a stopped app with `az functionapp start`. This is intended: a person should look at the
  traffic first, and restart only once the alert has resolved. The alerts are stateful, so an alert that is still
  "Fired" does not notify again; an app restarted during an ongoing flood would run without the burst alert's
  protection until the alert resolves and fires again (see docs/runbook.md).
- In staging, Cosmos DB runs serverless and has no provisioned throughput to cap. There, spending on the database
  is bounded by the function's scale caps (it is the only client), the kill switch and the environment's budget.
- Action groups notify the Logic App when an alert fires and again when it resolves. The first version stopped the
  app on every call, so the "Resolved" notification stopped an app that had just been restarted. The workflow now
  checks `monitorCondition` in the common alert schema and only acts on alerts that are not resolved.
- The alert threshold has to stay well below the throughput the scale caps allow. The first threshold of 3,000
  never fired during a flood test, because throttling kept every 5-minute window just under it. At 1,500 the
  alert fires.
- The action group must be given the trigger's callback URL. With the workflow-level URL from
  `listCallbackUrl()` the alert fired but no run started; the template now requests the trigger URL, and a
  flood test confirmed that the app stops.

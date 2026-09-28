# 6. Staging environment before production

- Status: accepted
- Date: 2026-09-29

## Context

Until now every merge went straight to production, so production was the first place a change ran on Azure.
The unit and emulator tests cover the code, but not the deployment itself: Bicep that validates but fails at
runtime, identity propagation, the function's cold start after a code deployment (which once returned 503 to
the smoke test).

## Decision

- One template, several parameter files: `infra/environments/{production,staging}.bicepparam`. Environments
  differ only in parameters, never in code.
- Staging has its own resource group, its own deploy identity and its own OIDC subject
  (`…:environment:staging`), so a staging run cannot touch production and the other way round. The bootstrap
  script creates both from the same code path.
- The Cosmos DB free tier exists once per subscription and belongs to production. Staging runs Cosmos DB
  serverless, which costs nothing while idle; its budget is lower.
- `deploy.yml` calls one reusable workflow twice: staging first, then production (`needs: staging`), both with
  the commit CI tested. Production still waits for the required reviewer, and only after staging passed its smoke
  test.

## Consequences

- A change that breaks the deployment or the live system stops in staging; production is untouched.
- The reviewer approves production knowing the same commit already deployed and passed the smoke test in
  staging, which makes the approval more meaningful than a what-if alone.
- A second copy of every resource exists. Idle cost stays near zero (serverless Cosmos DB, scale-to-zero
  functions, free Static Web Apps plan), and staging has its own budget and kill switch.

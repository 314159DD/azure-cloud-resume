# 3. OIDC federation and constrained RBAC for CI/CD

- Status: accepted
- Date: 2026-09-28

## Context

GitHub Actions deploys the infrastructure. The Bicep templates create role assignments (ADR 2), so the
pipeline identity must be allowed to grant roles, which is normally equivalent to Owner.

## Decision

- **No client secret.** An Entra application trusts GitHub's OIDC tokens for exactly two subjects:
  the `production` environment (deploy) and `pull_request` (what-if). Stale subjects are removed by the
  bootstrap script.
- Roles on the resource group only: **Contributor** plus **Role Based Access Control Administrator with an
  ABAC condition** that allows assigning and removing exactly the three roles the templates need.
- Subscription-level actions (resource provider registration) and the identity itself are created once by a
  human with `scripts/bootstrap.ps1`.

## Consequences

- A compromised workflow cannot escalate to Owner, cannot touch other resource groups and has no secret to exfiltrate.
- Adding a new role to the templates requires updating the condition in the bootstrap script, deliberately.

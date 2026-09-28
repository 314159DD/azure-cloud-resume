# 3. OIDC federation, constrained RBAC and no cloud access for pull requests

- Status: accepted
- Date: 2026-09-28

## Context

GitHub Actions deploys the infrastructure. The Bicep templates create role assignments (ADR 2), so the pipeline
identity must be allowed to grant roles, which normally amounts to Owner. A preview of infrastructure changes on
pull requests would also be useful.

## Decision

- There is no client secret. One Entra application trusts GitHub's OIDC tokens for a single subject, the
  `production` environment. That environment only accepts deployments from `main`, and the deploy workflow only
  runs after CI has passed on the same commit. GitHub puts immutable owner and repository IDs into the subject
  (`repo:314159DD@34370107/azure-cloud-resume@1393520300:environment:production`), so a repository recreated under
  the same name would not inherit the trust; the bootstrap script looks the IDs up.
- On the resource group the identity is Contributor plus Role Based Access Control Administrator. An ABAC condition
  limits the second role to assigning and removing the three Azure RBAC roles the templates use.
- Azure Policy assignments on the resource group deny re-enabling key-based access on Storage, Cosmos DB and
  Application Insights. Contributor cannot delete policy assignments, so the pipeline cannot turn keys back on.
- Pull requests get no Azure identity. ARM authorizes `what-if` like a real deployment: it checks write permission
  on every resource in the template. A read-only preview identity was tried and failed for exactly that reason,
  and any identity that can preview a pull request could also deploy from it. Pull requests are checked offline
  (lint, tests, Bicep build and lint, PSRule), and the `what-if` preview runs as the first step of the protected
  deploy job, where it is written to the job summary.
- Subscription-level setup (resource providers, the identity, the policy assignments) is done once by a person
  with Owner rights, using `scripts/bootstrap.ps1`.

## Consequences

- A compromised pull request has no cloud access. A compromised deploy workflow cannot become Owner, cannot reach
  other resource groups, cannot re-enable keys and has no secret to exfiltrate.
- One gap remains: Cosmos DB data-plane role assignments are managed through Contributor, not through
  `Microsoft.Authorization`, so the ABAC condition does not cover them. The deploy identity could grant itself read
  and write access to the counter data. For a public visitor count this is accepted; a workload with real data
  would add a policy that restricts `sqlRoleAssignments` to known principals.
- Reviewers see the infrastructure diff only after merging, in the deploy run. For this repository that is an
  acceptable trade for keeping cloud access away from pull requests.
- Adding a role to the templates means updating the condition in the bootstrap script on purpose.

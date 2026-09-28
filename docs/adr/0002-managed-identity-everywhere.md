# 2. Managed identity everywhere, keys disabled

- Status: accepted
- Date: 2026-09-28

## Context

The function needs its host storage, Application Insights and Cosmos DB. The default is connection strings
and account keys in app settings: long-lived secrets that leak into logs, screenshots and repos, and that
cannot be scoped or audited per caller.

## Decision

- One **user-assigned** managed identity for the function. It exists before the app, so its role assignments
  are in place before the first start (a system-assigned identity would start without permissions).
- Key-based access is **disabled** on every dependency: `allowSharedKeyAccess: false` (Storage),
  `disableLocalAuth: true` (Cosmos DB, Application Insights). A leaked key would not work.
- Least-privilege roles, scoped to the single resource or database:
  Storage Blob Data Owner, Monitoring Metrics Publisher, Cosmos DB Built-in Data Contributor (database scope,
  Cosmos data-plane RBAC).

## Consequences

- No secrets in app settings, the repository or the pipeline. Access is revoked by removing a role.
- Verified: removing the Cosmos data role makes the API fail immediately; there is no fallback path.
- Cosmos rejects scope changes on an existing role assignment, so the assignment name is derived from its scope.

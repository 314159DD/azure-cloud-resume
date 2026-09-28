# Verification log

What was tested against the live deployment, how, and what came out. Times are UTC, all on 2026-09-28.
Checks that can be repeated without disruption are scripted; the disruptive ones are scripted too but
meant to be run on purpose.

| Check | Repeat it with | Disruptive |
|---|---|---|
| Site headers, atomic counter, CORS | [`scripts/smoke-test.sh`](../scripts/smoke-test.sh) (runs after every deployment) | no |
| Keys stay off, no Owner escalation, no basic publishing credentials | [`scripts/verify-guardrails.sh`](../scripts/verify-guardrails.sh), or the **Verify guardrails** workflow | no |
| Throttling and kill switch | [`scripts/flood-test.sh`](../scripts/flood-test.sh) | yes, stops the API |

## Atomic counter

- 20 concurrent POSTs against the deployed API raised the public counter from 2 to 22 (18:37). The smoke test
  now runs the same check on a separate `smoke` counter and requires 20 distinct returned counts.
- Every deployment since runs it; the first green pipeline deployment (Actions run 36481719741) logged
  `OK: smoke counter 20 -> 40`.

## No fallback to keys

- 18:58: deleted the function's Cosmos DB data-plane role assignment. The next request returned HTTP 500
  (`Counter unavailable`). There is no key to fall back to.
- `az deployment group what-if` then listed exactly one `Create`: the missing role assignment (drift detected).
- 19:01: redeploy, the API answered 200 again.

## Keys cannot be turned back on

With the Azure Policy assignments in place, both attempts were refused, even for the subscription Owner:

```
az storage account update ... --allow-shared-key-access true                -> RequestDisallowedByPolicy
az resource update ... --set properties.disableLocalAuth=false (Cosmos DB)  -> RequestDisallowedByPolicy
```

`scripts/verify-guardrails.sh` repeats both, plus the check that the deploy identity cannot grant itself
Owner (refused by the ABAC condition).

## Pull requests cannot preview without deploy rights

A test identity with a custom role of `*/read`, `Microsoft.Resources/deployments/validate/action` and
`Microsoft.Resources/deployments/whatIf/action` ran `what-if` against the templates. ARM refused it with
`AuthorizationFailed` for `Microsoft.Resources/deployments/write` and the `.../write` action of every resource
in the template. The test identity and its role were deleted afterwards. This is why pull requests get no
Azure access ([ADR 3](adr/0003-oidc-and-constrained-rbac-for-ci.md)).

## Throttling and kill switch

Each flood sent 3,600 GET requests with 25 in parallel from one client.

| Run | Window (UTC) | Result |
|---|---|---|
| 1 | 18:36 to 18:41 | 3,404 × 200 and 196 connection errors in 284 s, about 12 requests/s through 1 instance × 10 concurrent requests. Per-minute executions arrived in batches (992, 960, 5, 10, 933, 508); the highest 5-minute window was about 2,900, just under the first threshold of 3,000, so the alert never fired. Threshold lowered to 1,500. |
| 2 | 18:53 to 18:58 | The alert fired at 18:58:49 (`ActionsTriggered`), but the Logic App never started: the action group had the workflow-level callback URL from `listCallbackUrl()` instead of the trigger URL. Fixed in the template. |
| 3 | 19:10 to 19:14 | The Logic App run started at 19:14:45 and succeeded; from 19:15 the API returned 403 ("This web app is stopped"). |

After run 3 the app was restarted at about 19:19 and was stopped again at 19:21:50 by the same alert, because
delayed metric batches still counted. Restart only once the alert shows "Resolved".

The kill switch later moved from the built-in Website Contributor role to a custom role that can only read,
stop and start the app. Triggering it directly returned 202, the run succeeded, the API returned 403, and
`az functionapp start` brought it back to 200.

## First pipeline runs

The pipeline was built and exercised locally first. Its first runs on GitHub found three problems:

| Run | Problem | Fix |
|---|---|---|
| before the repository went public | Jobs not started: private repositories need Actions billing on the account | repository made public |
| 36480866497 | `AADSTS700213`: GitHub now sends the OIDC subject with immutable IDs (`repo:314159DD@34370107/azure-cloud-resume@1393520300:environment:production`) | bootstrap reads the IDs from the GitHub API |
| 36481184047 | `Resource null of type Microsoft.Web/Sites`: ARM returned the output `AZURE_FUNCTION_APP_NAME` as `azurE_FUNCTION_APP_NAME` | camelCase outputs, and the workflow fails immediately if an output is missing |

Run 36481719741 was the first fully green deployment: OIDC login, what-if, infrastructure, API, site and smoke
test.

# Verification log

What was tested against the live deployment, how, and what came out. Times are UTC, on 2026-09-28 unless a date is given.
Checks that can be repeated without disruption are scripted; the disruptive ones are scripted too but
meant to be run on purpose.

| Check | Repeat it with | Disruptive |
|---|---|---|
| Site headers, atomic counter, CORS | [`scripts/smoke-test.sh`](../scripts/smoke-test.sh) (runs after every deployment) | no |
| Site and public counter are up (GET, no increment) | the hourly **Health check** workflow (`.github/workflows/health.yml`, no Azure login) | no |
| Keys stay off, no Owner escalation, no basic publishing credentials | [`scripts/verify-guardrails.sh`](../scripts/verify-guardrails.sh), or the **Verify guardrails** workflow | no |
| Throttling and kill switch | [`scripts/flood-test.sh`](../scripts/flood-test.sh) | yes, stops the API |
| Cosmos DB adapter (patch `incr`, 404, create race) | `npm run test:integration` against the emulator (CI job "API integration") | no |
| Private networking variant | the **Private network test** workflow (deploys, verifies, tears down) | no (separate resource group) |

## Atomic counter

- 20 concurrent POSTs against the deployed API raised the public counter from 2 to 22 (18:37). The smoke test
  now runs the same check on a separate `smoke` counter and requires 20 distinct returned counts.
- Every deployment since runs it; the first green pipeline deployment (Actions run 36481719741) logged
  `OK: smoke counter 20 -> 40`.

## No fallback to keys

- 18:58: deleted the function's Cosmos DB data-plane role assignment. The next request failed
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

After run 3 the app was restarted at about 19:19 and was stopped again at 19:21:50. The alert history shows
why: the alert resolved at 19:21:49, and the action group calls the Logic App for "Resolved" as well as for
"Fired". The workflow stopped the app on every call. It now reads `data.essentials.monitorCondition` from the
common alert schema and ignores "Resolved"; tested at 21:56 with a "Resolved" payload (API stayed at 200) and
a "Fired" payload at 21:57 (API 403, then restarted).

Evidence from Azure Monitor and the Logic App run history:

| Time | Event |
|---|---|
| 18:35:22 | Logic App run `08584109863625466502457217761CU03`, triggered directly (first manual test) |
| 18:58:49 to 19:05:44 | Burst alert fired and resolved; no run, because of the wrong callback URL |
| 19:14:41 | Burst alert fired; Logic App run `08584109839995317940191688383CU18` at 19:14:45 stopped the app |
| 19:21:49 | Alert resolved; run `08584109835745013097120992630CU10` at 19:21:50 stopped the restarted app (the bug above) |
| 21:03:30 | Run `08584109774749838572945771768CU22`, direct test of the custom stop/start role |
| 21:56:16, 21:57:01 | Runs `…415700CU16` ("Resolved", no stop) and `…210102678CU10` ("Fired", stop) after the fix |

The kill switch later moved from the built-in Website Contributor role to a custom role that can only read,
stop and start the app. Triggering it directly returned 202, the run succeeded, the API returned 403, and
`az functionapp start` brought it back to 200.

## Cosmos DB adapter against the emulator

The integration tests (`api/integration`) run in CI against the Linux Cosmos DB emulator as a service container.
First run on the pull request that added them: `ok 1 - first visit creates the counter, later visits increment
it`, `ok 2 - concurrent increments are atomic, including the create race on a new counter` (25 concurrent
increments on a new counter return 1 to 25 exactly once each), `# skipped 0`.

## Private networking variant

Deployed twice with `infra/environments/private-network-test.bicepparam` into throwaway resource groups
(2026-09-28, UTC), each deleted afterwards:

| Step | First run (`rg-cloudresume-nettest`) | Re-test with the final network module (`rg-cloudresume-nettest2`) |
|---|---|---|
| Deployment | 22:31 to 22:43; the private endpoint alone took 10 min 22 s | 23:05 to 23:17 |
| Configuration | Cosmos DB `publicNetworkAccess: Disabled`, serverless; private endpoint `Approved`; function integrated into `vnet-…/subnets/app` | same, plus an NSG on both subnets with `deny-outbound-ssh-rdp` (22, 3389) and `defaultOutboundAccess: false` on the endpoint subnet; workbook present |
| Counter through the private endpoint | `POST /api/visits` → 200 `{"count":2}` | 200 `{"count":1}` |
| Cosmos DB from the internet (developer PC, Entra token) | HTTP 403: "Request originated from IP … through public internet. This is blocked by your Cosmos DB account firewall settings." | same 403 |
| Resource group deleted | 22:50 to 23:07 | after the re-test |

Since pull request #4 the same test runs as the **Private network test** workflow. First run,
[36501356823](https://github.com/314159DD/azure-cloud-resume/actions/runs/36501356823): deployment, network
configuration check (`publicNetworkAccess: Disabled`, private endpoint `Approved`, function in `subnets/app`),
and counter through the private endpoint passed. The public-internet check only looked green (see the fourth run
below). The tear-down step failed and deleted
nothing: Application Insights creates an alert rule named "Failure Anomalies - …", and the unquoted list of
resource IDs was split on its spaces. The resources were deleted by hand right after, the step now reads the IDs
into an array, and the workflow was run again.

The second run, [36506420940](https://github.com/314159DD/azure-cloud-resume/actions/runs/36506420940), failed in
the deployment: the empty resource group meant a new managed identity, and Cosmos DB rejected its role
assignment with "The provided principal ID … was not found in the AAD tenant". The identity existed but had not
replicated through Entra ID yet. Together with the Cosmos DB lock on the first production attempt, that made two
transient platform errors, so deployments now go through `scripts/deploy-infra.sh`, which retries exactly these
two messages and fails on anything else.

The third run, [36565910686](https://github.com/314159DD/azure-cloud-resume/actions/runs/36565910686)
(2026-09-29, 12:06 to 12:25 UTC), deployed on the first attempt in 13 min 18 s and passed the configuration and counter checks. The
tear-down went red with two resources left, the Static Web App and the Cosmos DB account. Both deletes had been
accepted in the first pass: Cosmos DB answered the later passes with "There is already an operation in progress
which requires exclusive lock", and the Static Web App delete failed only while polling its operation status at
subscription scope, which the resource-group-scoped identity cannot read. The eight passes ran within three minutes
without waiting, so the step gave up while Azure was still deleting. Both finished on their own: the Cosmos DB
account was gone at 12:36, 13 minutes after the delete started. The Static Web App already answered "NotFound" at
12:26 but stayed in `az resource list` for longer. The step now starts deletes with `--no-wait`, repeats up to 30
passes a minute apart, and counts a listed resource as left only while `az resource show` still finds it.

The fourth run, [36569580410](https://github.com/314159DD/azure-cloud-resume/actions/runs/36569580410)
(2026-09-29, 12:39 to 13:15 UTC), finished green, including the tear-down (12:54 to 13:15, 21 resources, then 4,
2 and none; the first pass took 17 minutes because some deletes block despite `--no-wait`). Reading its log
before recording it showed that the green was not complete: the step "Cosmos DB refuses the public internet" had
printed

```
FAIL: unexpected response (HTTP undefined): Please run 'az login' from a command prompt to authenticate before using this credential.
```

and still passed, because the step piped the probe into `tee` and the default shell of a `run` step has no
`pipefail`. The first and third runs printed the same line. So the public-internet 403 was never shown by the
workflow, only by the manual test from a developer PC in the table above. The probe itself did not reach Cosmos
DB: it needs a new Entra token for Cosmos DB 14 minutes after `azure/login`, when the federated credential from
the GitHub OIDC token has expired. Changes: the Azure workflows (deploy, network test and verify) set `shell: bash` (which adds `pipefail`), and the
network test signs in again right before the probe.

The fifth run, [36574307186](https://github.com/314159DD/azure-cloud-resume/actions/runs/36574307186)
(2026-09-29, 13:20 to 13:56 UTC), is the first one where every check is shown by the workflow itself:

| Step | Result |
|---|---|
| Deployment | 13:20 to 13:33 (766 s), first attempt |
| Network configuration | `publicNetworkAccess: Disabled`, private endpoint `Approved`, function in `vnet-…/subnets/app` |
| Counter through the private endpoint | `POST /api/visits?id=smoke` → `{"count":1}` |
| Cosmos DB from the internet (GitHub runner, fresh login) | `PASS: refused from the public internet (HTTP 403): Request originated from IP … through public internet. This is blocked by your Cosmos DB account firewall settings.` |
| Tear-down | 21 resources, then 4, 2 and none; "Resource group empty after 3 deletion pass(es), 20 min 53 s" |

The first manual run was made before NSGs were added (PSRule for Azure flagged `Azure.VNET.UseNSGs` and
`Azure.NSG.LateralTraversal`), which is why the variant was deployed and tested a second time.

## First pipeline runs

The pipeline was built and exercised locally first. Its first runs on GitHub found three problems:

| Run | Problem | Fix |
|---|---|---|
| before the repository went public | Jobs not started: private repositories need Actions billing on the account | repository made public |
| 36480866497 | `AADSTS700213`: GitHub now sends the OIDC subject with immutable IDs (`repo:314159DD@34370107/azure-cloud-resume@1393520300:environment:production`) | bootstrap reads the IDs from the GitHub API |
| 36481184047 | `Resource null of type Microsoft.Web/Sites`: ARM returned the output `AZURE_FUNCTION_APP_NAME` as `azurE_FUNCTION_APP_NAME` | camelCase outputs, and the workflow fails immediately if an output is missing |

Run 36481719741 was the first fully green deployment: OIDC login, what-if, infrastructure, API, site and smoke
test. The commit it shows (`b14633d`) no longer exists under that hash: the history was rewritten once on the
same evening to correct the author name, which changed every hash. The content is unchanged.

Later runs, after the production environment got a required reviewer:

| Run | Result |
|---|---|
| [36484234169](https://github.com/314159DD/azure-cloud-resume/actions/runs/36484234169) | Deployed, but the smoke test failed: two of the 20 concurrent POSTs got HTTP 503 while the function restarted after the code deployment. App Insights showed no 503 from the handler, so the platform answered before the worker did. The smoke test now retries transient failures per request. |
| [36485803598](https://github.com/314159DD/azure-cloud-resume/actions/runs/36485803598) | Green, smoke test `98 -> 118` with 20 distinct counts. |
| [36485870155](https://github.com/314159DD/azure-cloud-resume/actions/runs/36485870155) (Verify guardrails) | Green as the deploy identity: enabling keys on Storage and Cosmos DB refused with `RequestDisallowedByPolicy`, granting itself Owner refused with `AuthorizationFailed`, keys and basic publishing credentials off. |

With the staging environment (pull request #3):

| Run | Result |
|---|---|
| [36497866294](https://github.com/314159DD/azure-cloud-resume/actions/runs/36497866294) | Staging, first deployment into its new resource group: green, smoke test `0 -> 20` with the staging identity. Production, first attempt: the Bicep deployment failed with `PreconditionFailed`, "an operation in progress which requires exclusive lock" on the production Cosmos DB account; nothing was changed and the live API kept answering. The lock had cleared a few minutes later (`provisioningState: Succeeded`); re-running the failed job succeeded with smoke test `158 -> 178`. |
| [36500105462](https://github.com/314159DD/azure-cloud-resume/actions/runs/36500105462) (Verify guardrails) | Green in both environments, each with its own deploy identity: 7 of 7 checks passed in staging and in production. |

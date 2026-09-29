# Runbook: the kill switch stopped the API

The site keeps working; the visitor counter shows "unavailable" and the API answers 403
("This web app is stopped"). You received an e-mail from the `ag-…-killswitch` action group.

## 1. Confirm what fired

```bash
RG=rg-cloudresume
az monitor metrics alert list -g $RG --query "[].{name:name, enabled:enabled}" -o table
# Fired and resolved alerts of the last day, newest first
az rest --method get --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&timeRange=1d" \
  --query "value[].{rule:properties.essentials.alertRule, state:properties.essentials.monitorCondition, fired:properties.essentials.startDateTime}" -o table
```

- `alert-…-executions-burst`: more than 1,500 executions in 5 minutes.
- `alert-…-executions-sustained`: more than 20,000 executions in 24 hours.
- No metric alert fired: the budget reached 100 % (check Cost Management for the resource group).

## 2. Look at the traffic

Open the workbook **Cloud resume operations** (resource group → Workbooks). The first chart shows requests per
5 minutes against the burst threshold. Or query Application Insights directly:

```kusto
requests
| where timestamp > ago(2h)
| summarize requests = count() by bin(timestamp, 1m), client_IP, resultCode
| order by requests desc
```

Decide whether it was abuse (one client, a burst far above normal) or legitimate traffic (for example the
site being shared widely). For abuse, stop here and leave the API off until it has ended; for a real audience,
consider raising `burstThreshold` in `infra/environments/<env>.bicepparam` through a pull request.

## 3. Check the cost impact

```bash
az consumption usage list --start-date $(date -u -d '-2 days' +%F) --end-date $(date -u +%F) \
  --query "[?contains(instanceId, '$RG')].{resource:instanceName, cost:pretaxCost}" -o table
```

Cost data lags by several hours; the scale caps (1 instance, 10 concurrent requests) bound compute in the
meantime.

## 4. Restart and verify

```bash
FUNC=$(az functionapp list -g $RG --query "[0].name" -o tsv)
az functionapp start -g $RG -n $FUNC
./scripts/smoke-test.sh "https://$FUNC.azurewebsites.net/api" "<site url from the README>"
```

Restart only after the alert shows "Resolved" (step 1). The alerts are stateful: while one is in the "Fired"
state it does not notify again, so an app restarted during an ongoing flood would stay up without the burst
alert's protection until that alert resolves and fires anew (the 24-hour alert and the budget still apply).
The kill switch ignores the "Resolved" notification itself, so waiting for it does not stop the app again.

## 5. Afterwards

- Note the incident (time, cause, cost) in `docs/verification.md` if it taught something new.
- If thresholds changed, deploy them through a pull request so staging runs first.

# Runbook: the API is failing but was not stopped

You received an e-mail from the `ag-�-ops` action group (alert `alert-�-failed-requests`: more than 5 failed
requests in 15 minutes), or the hourly **Health check** workflow failed. The kill switch did not fire, so this is
a broken API and not a flood. The alert only notifies; it never stops the app.

## 1. Confirm

- Open the failed **Health check** run. Its log shows which request failed (site, `/config.js`, or the counter GET).
- Ask the API directly. A healthy answer is 200 with `{"count":<number>}`:

```bash
curl -i "https://<function app>.azurewebsites.net/api/visits"
```

- Check the app state and the recent failures:

```bash
RG=rg-cloudresume
FUNC=$(az functionapp list -g $RG --query "[0].name" -o tsv)
az functionapp show -g $RG -n $FUNC --query state -o tsv   # Running, or Stopped after the kill switch
az monitor app-insights query -g $RG --app appi-<suffix> --offset 2h --analytics-query   "requests | where success == false | summarize n = count() by resultCode, bin(timestamp, 15m)"
az monitor app-insights query -g $RG --app appi-<suffix> --offset 2h --analytics-query   "exceptions | project timestamp, type, outerMessage | order by timestamp desc | take 20"
```

## 2. Common causes

| Symptom | Cause | Action |
|---|---|---|
| 503 `Counter unavailable` | The function's Cosmos DB data-plane role assignment is missing or the account is unreachable. There is no key to fall back to ([verification](verification.md), "No fallback to keys"). | Redeploy the infrastructure (step 3). |
| 403 "This web app is stopped" | The kill switch stopped the app. | Follow the kill-switch runbook above. |
| 429 from Cosmos DB in `exceptions` | The 1,000 RU/s cap throttles requests. | Look for a burst in `requests`; it usually passes on its own. |
| Failures start right after a deployment | A bad release. | Revert the commit in a pull request; the merge deploys the previous state through staging first. |

## 3. Recover

Deploying the infrastructure again restores a drifted role assignment: merge a change to `main`, or run the
**CI** workflow manually on `main`, which starts the **Deploy** workflow. Verify with
`./scripts/smoke-test.sh "https://$FUNC.azurewebsites.net/api" "<site url from the README>"`. The alert resolves
itself once failures stop, and the next hourly **Health check** run turns green.


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

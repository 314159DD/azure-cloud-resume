// Automatic stop for runaway cost.
//
// Budgets and alerts only notify. For a usage-billed API the only hard stop is automation:
//   execution alerts (burst, sustained) and the exhausted budget
//     -> action group -> Logic App (managed identity) -> POST .../stop on the Function App
// The Logic App may only stop/start this one Function App (custom role limited to read, stop and start, scoped to the app).
// Re-enable after investigating: az functionapp start -g <rg> -n <app>
param location string
param namePrefix string
param tags object
param functionAppName string
param alertEmail string

@description('''Executions per 5 minutes that count as a flood (1500 = 5 requests/s).
Must sit well below what the scale caps allow (about 12 requests/s measured with 1 instance and
10 concurrent requests), otherwise throttling keeps the metric under the threshold and it never fires.''')
param burstThreshold int = 1500

@description('''Executions per 24 hours that count as abuse (20000 = 0.23 requests/s on average).
Catches steady traffic that stays just under the burst threshold, well before the lagging budget would.''')
param sustainedThreshold int = 20000

var executionAlerts = [
  { name: 'burst', description: 'Flood of requests', frequency: 'PT1M', window: 'PT5M', threshold: burstThreshold }
  { name: 'sustained', description: 'Sustained abuse below the burst threshold', frequency: 'PT1H', window: 'P1D', threshold: sustainedThreshold }
]

// "Cloud Resume Function Stopper": custom role created by scripts/bootstrap.ps1 (sites/read, stop, start).
var roleFunctionStopper = 'a9567326-3f0c-4ec2-a9c0-8af4236ffe24'

resource functionApp 'Microsoft.Web/sites@2024-04-01' existing = {
  name: functionAppName
}

resource stopper 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'logic-${namePrefix}-killswitch'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        alert: {
          type: 'Request'
          kind: 'Http'
          inputs: { schema: {} }
        }
      }
      actions: {
        stopFunctionApp: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${environment().resourceManager}${substring(functionApp.id, 1)}/stop?api-version=2024-04-01'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: environment().resourceManager
            }
          }
        }
      }
    }
  }
}

resource stopperRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: functionApp
  name: guid(functionApp.id, stopper.id, roleFunctionStopper)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleFunctionStopper)
    principalId: stopper.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource killSwitchGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${namePrefix}-killswitch'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'killswitch'
    enabled: true
    emailReceivers: [
      { name: 'owner', emailAddress: alertEmail, useCommonAlertSchema: true }
    ]
    logicAppReceivers: [
      {
        name: 'stop-function-app'
        resourceId: stopper.id
        // Must be the trigger's callback URL. The workflow-level listCallbackUrl() returns a URL that
        // the action group accepts but that never starts a run (found by the flood test).
        callbackUrl: listCallbackUrl('${stopper.id}/triggers/alert', '2019-05-01').value
        useCommonAlertSchema: true
      }
    ]
  }
}

resource executionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for alert in executionAlerts: {
    name: 'alert-${namePrefix}-executions-${alert.name}'
    location: 'global'
    tags: tags
    properties: {
      description: '${alert.description}: stops the Function App.'
      severity: 1
      enabled: true
      scopes: [functionApp.id]
      autoMitigate: true
      evaluationFrequency: alert.frequency
      windowSize: alert.window
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
        allOf: [
          {
            criterionType: 'StaticThresholdCriterion'
            name: 'executions'
            metricNamespace: 'Microsoft.Web/sites'
            metricName: 'OnDemandFunctionExecutionCount'
            operator: 'GreaterThan'
            threshold: alert.threshold
            timeAggregation: 'Total'
          }
        ]
      }
      actions: [{ actionGroupId: killSwitchGroup.id }]
    }
  }
]

output actionGroupId string = killSwitchGroup.id

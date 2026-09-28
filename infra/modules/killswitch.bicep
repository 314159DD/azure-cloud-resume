// Cost guardrails that act, not just warn.
//
// Budgets and alerts only notify. For a usage-billed API the only hard stop is automation:
//   execution-count alert  --\
//                             >-- action group --> Logic App (managed identity) --> POST .../stop
//   budget exceeded ---------/
// The Logic App may only stop/start this one Function App ("Website Contributor" scoped to it).
// Re-enable after investigating: az functionapp start -g <rg> -n <app>
param location string
param namePrefix string
param tags object
param functionAppName string
param alertEmail string

@description('''Executions per 5 minutes that count as abuse (1500 = 5 requests/s sustained).
Must sit well below what the scale caps allow (about 12 requests/s measured with 1 instance and
10 concurrent requests), otherwise throttling keeps the metric under the threshold and it never fires.''')
param executionThreshold int = 1500

var roleWebsiteContributor = 'de139f84-1756-47ae-9be6-808fbbe84772'

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
  name: guid(functionApp.id, stopper.id, roleWebsiteContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleWebsiteContributor)
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

resource floodAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-${namePrefix}-execution-flood'
  location: 'global'
  tags: tags
  properties: {
    description: 'Stops the Function App when executions exceed the abuse threshold.'
    severity: 1
    enabled: true
    scopes: [functionApp.id]
    autoMitigate: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'executions'
          metricNamespace: 'Microsoft.Web/sites'
          metricName: 'OnDemandFunctionExecutionCount'
          operator: 'GreaterThan'
          threshold: executionThreshold
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [{ actionGroupId: killSwitchGroup.id }]
  }
}

output actionGroupId string = killSwitchGroup.id

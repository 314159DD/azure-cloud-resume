// E-mail alert for a failing API. The kill switch only watches execution volume, so nobody hears about an API
// that is down or failing at normal traffic (for example after the Cosmos DB role assignment was removed and
// every request returns 503). It counts server errors only. A stopped app logs no requests at all; the hourly
// Health check workflow covers that case. This alert only notifies: its action group has no Logic App, so it
// never stops the app.
param namePrefix string
param tags object
param appInsightsName string
param alertEmail string

@description('''Server errors (5xx) within the 15 minute window that raise the alert. Client errors do not count:
an unknown counter id returns 400, and a few such requests from a scanner should not page anyone.''')
param failedRequestsThreshold int = 5

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource opsGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${namePrefix}-ops'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'ops'
    enabled: true
    emailReceivers: [
      { name: 'owner', emailAddress: alertEmail, useCommonAlertSchema: true }
    ]
  }
}

resource failedRequestsAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-${namePrefix}-failed-requests'
  location: 'global'
  tags: tags
  properties: {
    description: 'More than ${failedRequestsThreshold} API requests answered with a 5xx in 15 minutes: notifies only, does not stop the app.'
    severity: 2
    enabled: true
    scopes: [appInsights.id]
    autoMitigate: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'failed-requests'
          metricNamespace: 'microsoft.insights/components'
          metricName: 'requests/failed'
          operator: 'GreaterThan'
          threshold: failedRequestsThreshold
          timeAggregation: 'Count'
          dimensions: [
            { name: 'request/resultCode', operator: 'Include', values: ['500', '502', '503', '504'] }
          ]
        }
      ]
    }
    actions: [{ actionGroupId: opsGroup.id }]
  }
}

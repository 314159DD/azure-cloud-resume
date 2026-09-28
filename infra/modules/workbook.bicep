// Azure Monitor workbook: the operator's view for the runbook (docs/runbook.md). Queries Application Insights:
// request volume against the kill-switch thresholds, failures by status, and latency including cold starts.
param location string
param namePrefix string
param tags object
param appInsightsId string

@description('Burst threshold of the kill switch (executions per 5 minutes), drawn as a reference line.')
param burstThreshold int

var queries = [
  {
    title: 'Requests per 5 minutes vs. kill-switch burst threshold'
    query: 'requests | where timestamp > ago(24h) | summarize requests = count() by bin(timestamp, 5m) | extend threshold = ${burstThreshold} | render timechart'
    visualization: 'timechart'
  }
  {
    title: 'Responses by status code (24 h)'
    query: 'requests | where timestamp > ago(24h) | summarize count() by resultCode | order by count_ desc'
    visualization: 'piechart'
  }
  {
    title: 'Failed requests (24 h)'
    query: 'requests | where timestamp > ago(24h) and success == false | project timestamp, name, resultCode, duration, operation_Id | order by timestamp desc | take 50'
    visualization: 'table'
  }
  {
    title: 'Latency p50 / p95 / max, including cold starts (24 h)'
    query: 'requests | where timestamp > ago(24h) | summarize p50 = percentile(duration, 50), p95 = percentile(duration, 95), max = max(duration) by bin(timestamp, 1h) | render timechart'
    visualization: 'timechart'
  }
]

var items = concat(
  [
    {
      type: 1
      content: { json: '## ${namePrefix}\nSee docs/runbook.md for what to do when the kill switch fires.' }
      name: 'header'
    }
  ],
  map(range(0, length(queries)), i => {
    type: 3
    content: {
      version: 'KqlItem/1.0'
      title: queries[i].title
      query: queries[i].query
      size: 0
      queryType: 0
      resourceType: 'microsoft.insights/components'
      visualization: queries[i].visualization
    }
    name: 'query-${i}'
  })
)

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'operations-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Cloud resume operations (${namePrefix})'
    category: 'workbook'
    sourceId: appInsightsId
    serializedData: string({
      version: 'Notebook/1.0'
      items: items
      fallbackResourceIds: [appInsightsId]
    })
  }
}

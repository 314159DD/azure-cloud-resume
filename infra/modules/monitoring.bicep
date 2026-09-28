// Logs and telemetry. Log Analytics bills per GB ingested, so ingestion has a hard daily cap.
param location string
param namePrefix string
param tags object

@description('Hard daily ingestion cap in GB. Keeps a log flood inside the free allowance.')
param dailyQuotaGb string = '0.1'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${namePrefix}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: json(dailyQuotaGb) }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${namePrefix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    // Entra-only ingestion: the connection string alone cannot be used to send telemetry.
    DisableLocalAuth: true
  }
}

output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString

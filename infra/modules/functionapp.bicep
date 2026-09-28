// Function App on the Flex Consumption plan (Linux, Node 22, scale to zero).
// Identity: a user-assigned managed identity. It exists before the app, so its role assignments are
// in place before the first cold start (no chicken-and-egg with a system-assigned identity).
param location string
param namePrefix string
param tags object
param storageName string
param deploymentContainerUrl string
param appInsightsName string
param cosmosAccountName string
param cosmosEndpoint string
param cosmosDatabaseName string
param cosmosContainerName string
param allowedOrigins array

@description('Cost ceiling: the platform never runs more instances than this, whatever the traffic.')
@minValue(1)
param maximumInstanceCount int = 1

@description('Concurrent HTTP requests per instance. Together with maximumInstanceCount this bounds throughput.')
@minValue(1)
param httpPerInstanceConcurrency int = 10

@allowed([512, 2048, 4096])
param instanceMemoryMB int = 512

// Built-in role definition IDs (identical in every tenant)
var roleStorageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var roleMonitoringMetricsPublisher = '3913510d-42f4-4e42-8a64-420c390055eb'
// Cosmos DB data plane: "Cosmos DB Built-in Data Contributor"
var cosmosBuiltInDataContributor = '00000000-0000-0000-0000-000000000002'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosAccountName
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${namePrefix}-func'
  location: location
  tags: tags
}

resource storageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, identity.id, roleStorageBlobDataOwner)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDataOwner)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource monitoringRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appInsights
  name: guid(appInsights.id, identity.id, roleMonitoringMetricsPublisher)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleMonitoringMetricsPublisher)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cosmos DB has its own RBAC system for the data plane (not Microsoft.Authorization).
// Least privilege: only this database, not the whole account.
var cosmosDataScope = '${cosmos.id}/dbs/${cosmosDatabaseName}'

resource cosmosDataRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmos
  // The scope is part of the name because Cosmos rejects scope updates on an existing assignment:
  // changing the scope must create a new assignment instead.
  name: guid(cosmosDataScope, identity.id, cosmosBuiltInDataContributor)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosBuiltInDataContributor}'
    principalId: identity.properties.principalId
    scope: cosmosDataScope
  }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-${namePrefix}'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'func-${namePrefix}'
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false // stateless API, no sticky sessions
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: deploymentContainerUrl
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identity.id
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
        triggers: { http: { perInstanceConcurrency: httpPerInstanceConcurrency } }
      }
      runtime: { name: 'node', version: '22' }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      cors: { allowedOrigins: allowedOrigins }
      appSettings: [
        // Host storage via managed identity instead of a connection string
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'AzureWebJobsStorage__clientId', value: identity.properties.clientId }
        { name: 'AzureWebJobsStorage__blobServiceUri', value: 'https://${storage.name}.blob.${environment().suffixes.storage}' }
        // Telemetry via managed identity (App Insights rejects key-based ingestion)
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING', value: 'ClientId=${identity.properties.clientId};Authorization=AAD' }
        // Tells DefaultAzureCredential which identity to use
        { name: 'AZURE_CLIENT_ID', value: identity.properties.clientId }
        { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
        { name: 'COSMOS_DATABASE', value: cosmosDatabaseName }
        { name: 'COSMOS_CONTAINER', value: cosmosContainerName }
      ]
    }
  }
  dependsOn: [storageRole, monitoringRole, cosmosDataRole]
}

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output apiBaseUrl string = 'https://${functionApp.properties.defaultHostName}/api'

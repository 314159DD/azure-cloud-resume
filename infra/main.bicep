// Cloud Resume on Azure. Everything that exists is declared here; anything not declared here
// should not exist (drift shows up in `what-if`). One template, several environments: production,
// staging and throwaway test deployments differ only in their parameter files.
targetScope = 'resourceGroup'

@description('Environment name, used in tags and the workbook title.')
@allowed(['production', 'staging', 'test'])
param environmentName string = 'production'

@description('Region for all regional resources. New free-trial subscriptions are not admitted to every region.')
param location string = resourceGroup().location

@description('Static Web Apps Free is only offered in a few regions. Content is served globally either way.')
param siteLocation string = location

@description('Receives budget and kill-switch notifications.')
param alertEmail string

@description('First day of the month the budget starts (yyyy-MM-01).')
param budgetStartDate string

@description('Monthly budget in the billing currency; the kill switch fires when actual spend reaches it.')
param budgetAmount int = 5

@description('Cosmos DB capacity: the free tier exists once per subscription, other environments run serverless.')
@allowed(['freeTier', 'serverless'])
param cosmosCapacityMode string = 'freeTier'

@description('Reach Cosmos DB through a private endpoint in a VNet and disable its public access (billed per hour).')
param privateNetworking bool = false

@description('Kill-switch burst threshold: executions per 5 minutes.')
param burstThreshold int = 1500

var suffix = take(uniqueString(resourceGroup().id), 6)
var namePrefix = 'cloudresume-${suffix}'
var tags = {
  project: 'cloudresume'
  environment: environmentName
  owner: 'steven'
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: { location: location, namePrefix: namePrefix, tags: tags }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: { location: location, storageName: 'stcloudresume${suffix}', tags: tags }
}

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    location: location
    accountName: 'cosmos-${namePrefix}'
    tags: tags
    capacityMode: cosmosCapacityMode
    privateNetworking: privateNetworking
  }
}

module network 'modules/network.bicep' = if (privateNetworking) {
  name: 'network'
  params: { location: location, namePrefix: namePrefix, tags: tags, cosmosAccountId: cosmos.outputs.accountId }
}

module site 'modules/staticwebapp.bicep' = {
  name: 'site'
  params: { location: siteLocation, namePrefix: namePrefix, tags: tags }
}

module api 'modules/functionapp.bicep' = {
  name: 'api'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
    storageName: storage.outputs.storageName
    deploymentContainerUrl: storage.outputs.deploymentContainerUrl
    appInsightsName: monitoring.outputs.appInsightsName
    cosmosAccountName: cosmos.outputs.accountName
    cosmosEndpoint: cosmos.outputs.endpoint
    cosmosDatabaseName: cosmos.outputs.databaseName
    cosmosContainerName: cosmos.outputs.containerName
    // Browsers may call the API from the site only
    allowedOrigins: ['https://${site.outputs.defaultHostname}']
    appSubnetId: privateNetworking ? network!.outputs.appSubnetId : ''
  }
}

module killSwitch 'modules/killswitch.bicep' = {
  name: 'killswitch'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
    functionAppName: api.outputs.functionAppName
    alertEmail: alertEmail
    burstThreshold: burstThreshold
  }
}

module workbook 'modules/workbook.bicep' = {
  name: 'workbook'
  params: {
    location: location
    namePrefix: '${namePrefix} (${environmentName})'
    tags: tags
    appInsightsId: resourceId('Microsoft.Insights/components', monitoring.outputs.appInsightsName)
    burstThreshold: burstThreshold
  }
}

module budget 'modules/budget.bicep' = {
  name: 'budget'
  params: {
    namePrefix: namePrefix
    alertEmail: alertEmail
    startDate: budgetStartDate
    amount: budgetAmount
    killSwitchActionGroupId: killSwitch.outputs.actionGroupId
  }
}

output functionAppName string = api.outputs.functionAppName
output staticWebAppName string = site.outputs.name
output apiBaseUrl string = api.outputs.apiBaseUrl
output siteUrl string = 'https://${site.outputs.defaultHostname}'

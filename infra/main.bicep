// Cloud Resume on Azure. Everything that exists is declared here; anything not declared here
// should not exist (drift shows up in `what-if`).
targetScope = 'resourceGroup'

@description('Region for all regional resources. New free-trial subscriptions are not admitted to every region.')
param location string = resourceGroup().location

@description('Static Web Apps Free is only offered in a few regions. Content is served globally either way.')
param siteLocation string = location

@description('Receives budget and kill-switch notifications.')
param alertEmail string

@description('First day of the month the budget starts (yyyy-MM-01).')
param budgetStartDate string

@description('Cosmos DB free tier is limited to one account per subscription.')
param cosmosFreeTier bool = true

var suffix = take(uniqueString(resourceGroup().id), 6)
var namePrefix = 'cloudresume-${suffix}'
var tags = {
  project: 'cloudresume'
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
    enableFreeTier: cosmosFreeTier
  }
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
  }
}

module budget 'modules/budget.bicep' = {
  name: 'budget'
  params: {
    namePrefix: namePrefix
    alertEmail: alertEmail
    startDate: budgetStartDate
    killSwitchActionGroupId: killSwitch.outputs.actionGroupId
  }
}

output AZURE_FUNCTION_APP_NAME string = api.outputs.functionAppName
output AZURE_STATIC_WEB_APP_NAME string = site.outputs.name
output API_BASE_URL string = api.outputs.apiBaseUrl
output SITE_URL string = 'https://${site.outputs.defaultHostname}'

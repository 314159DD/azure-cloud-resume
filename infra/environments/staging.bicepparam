using '../main.bicep'

param environmentName = 'staging'
param location = 'germanywestcentral'
param siteLocation = 'eastus2'

// The Cosmos DB free tier is taken by production (one per subscription); serverless costs nothing while idle.
param cosmosCapacityMode = 'serverless'
param privateNetworking = false
param budgetAmount = 2

param alertEmail = readEnvironmentVariable('BUDGET_ALERT_EMAIL')
param budgetStartDate = readEnvironmentVariable('BUDGET_START_DATE', '2026-09-01')

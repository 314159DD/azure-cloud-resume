using '../main.bicep'

// Throwaway deployment that verifies the private-networking variant (see docs/verification.md).
// Deploy it into its own resource group, test, then delete the resource group.
param environmentName = 'test'
param location = 'germanywestcentral'
param siteLocation = 'eastus2'

param cosmosCapacityMode = 'serverless'
param privateNetworking = true
param budgetAmount = 2

param alertEmail = readEnvironmentVariable('BUDGET_ALERT_EMAIL')
param budgetStartDate = readEnvironmentVariable('BUDGET_START_DATE', '2026-09-01')

using '../main.bicep'

param environmentName = 'production'

// West Europe does not admit new free-trial subscriptions at the moment (RequestDisallowedByAzure).
// Data (Cosmos DB, Storage, logs) stays in Germany.
param location = 'germanywestcentral'
// Static Web Apps Free is not offered in Germany; the static content is served globally anyway.
param siteLocation = 'eastus2'

param cosmosCapacityMode = 'freeTier'
param privateNetworking = false
param budgetAmount = 5

// Not committed: provided by the environment (local shell or a GitHub Actions secret).
param alertEmail = readEnvironmentVariable('BUDGET_ALERT_EMAIL')
param budgetStartDate = readEnvironmentVariable('BUDGET_START_DATE', '2026-09-01')

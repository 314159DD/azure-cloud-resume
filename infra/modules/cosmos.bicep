// Cosmos DB for NoSQL. Key-based auth is disabled; data access is granted through Cosmos data-plane RBAC only.
//
// Capacity modes:
// - freeTier:   1000 RU/s and 25 GB at no cost, one free-tier account per subscription (production).
// - serverless: billed per request unit consumed, nothing while idle (staging and throwaway environments).
param location string
param accountName string
param tags object

@allowed(['freeTier', 'serverless'])
param capacityMode string = 'freeTier'

@description('Private networking: public network access is disabled and the account is reached through a private endpoint.')
param privateNetworking bool = false

var databaseName = 'cloudresume'
var containerName = 'counters'
var isFreeTier = capacityMode == 'freeTier'

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: isFreeTier
    capabilities: isFreeTier ? [] : [{ name: 'EnableServerless' }]
    disableLocalAuth: true
    disableKeyBasedMetadataWriteAccess: true
    minimalTlsVersion: 'Tls12'
    publicNetworkAccess: privateNetworking ? 'Disabled' : 'Enabled'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    // Point-in-time restore for the last 7 days; the 7-day tier has no backup storage charge.
    backupPolicy: { type: 'Continuous', continuousModeProperties: { tier: 'Continuous7Days' } }
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: false }]
    // Hard throughput ceiling at the free-tier size: excess requests get HTTP 429 instead of a bill.
    // Serverless accounts have no provisioned throughput to cap.
    capacity: isFreeTier ? { totalThroughputLimit: 1000 } : null
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: { id: databaseName }
    options: isFreeTier ? { throughput: 1000 } : {}
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      // One document per counter, so the id is a sufficient partition key here.
      partitionKey: { paths: ['/id'], kind: 'Hash' }
    }
  }
}

output accountId string = account.id
output accountName string = account.name
output endpoint string = account.properties.documentEndpoint
output databaseName string = databaseName
output containerName string = containerName

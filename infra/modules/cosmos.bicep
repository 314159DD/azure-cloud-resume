// Cosmos DB (NoSQL) on the free tier: 1000 RU/s and 25 GB at no cost, one free account per subscription.
// Key-based auth is disabled; data access is granted through Cosmos data-plane RBAC only.
param location string
param accountName string
param tags object
param enableFreeTier bool = true

var databaseName = 'cloudresume'
var containerName = 'counters'

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: enableFreeTier
    disableLocalAuth: true
    disableKeyBasedMetadataWriteAccess: true
    minimalTlsVersion: 'Tls12'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    // Point-in-time restore for the last 7 days; the 7-day tier has no backup storage charge.
    backupPolicy: { type: 'Continuous', continuousModeProperties: { tier: 'Continuous7Days' } }
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: false }]
    // Hard throughput ceiling at the free-tier size: excess requests get HTTP 429 instead of a bill.
    capacity: { totalThroughputLimit: 1000 }
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: { id: databaseName }
    options: { throughput: 1000 }
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

output accountName string = account.name
output endpoint string = account.properties.documentEndpoint
output databaseName string = databaseName
output containerName string = containerName

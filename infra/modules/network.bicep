// Optional private networking: the function reaches Cosmos DB through a private endpoint inside a virtual
// network, and Cosmos DB refuses public traffic.
//
//   Function App --(VNet integration, subnet "app")--> private endpoint (subnet "endpoints") --> Cosmos DB
//   privatelink.documents.azure.com (private DNS zone, linked to the VNet) resolves the account to the endpoint.
//
// Cost: the private endpoint and the DNS zone are billed per hour and per month; the VNet itself is free.
// Host storage stays on its public endpoint (RBAC-only, shared keys disabled): Flex Consumption deploys the
// code package through it.
param location string
param namePrefix string
param tags object
param cosmosAccountId string

@description('Address space of the virtual network.')
param addressPrefix string = '10.20.0.0/24'

// One network security group per subnet. Besides the default rules (traffic inside the VNet, outbound to the
// internet) both deny outbound SSH and RDP: nothing here administers machines, so a compromised workload
// should not be able to move laterally over those protocols.
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = [
  for subnet in ['app', 'endpoints']: {
    name: 'nsg-${namePrefix}-${subnet}'
    location: location
    tags: tags
    properties: {
      securityRules: [
        {
          name: 'deny-outbound-ssh-rdp'
          properties: {
            priority: 100
            direction: 'Outbound'
            access: 'Deny'
            protocol: '*'
            sourceAddressPrefix: '*'
            sourcePortRange: '*'
            destinationAddressPrefix: '*'
            destinationPortRanges: ['22', '3389']
          }
        }
      ]
    }
  }
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${namePrefix}'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressPrefix] }
    subnets: [
      {
        name: 'app'
        properties: {
          addressPrefix: cidrSubnet(addressPrefix, 26, 0)
          // Flex Consumption integrates through a subnet delegated to Microsoft.App/environments.
          delegations: [{ name: 'flex', properties: { serviceName: 'Microsoft.App/environments' } }]
          networkSecurityGroup: { id: nsg[0].id }
          // Keeps default outbound access: the function needs Entra ID, host storage and Application Insights,
          // and without it a NAT gateway (billed per hour) would be required.
        }
      }
      {
        name: 'endpoints'
        properties: {
          addressPrefix: cidrSubnet(addressPrefix, 27, 2)
          privateEndpointNetworkPolicies: 'Disabled'
          networkSecurityGroup: { id: nsg[1].id }
          // Private endpoints never initiate outbound connections.
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
  tags: tags
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZone
  name: 'link-${namePrefix}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}

resource cosmosEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${namePrefix}-cosmos'
  location: location
  tags: tags
  properties: {
    subnet: { id: vnet.properties.subnets[1].id }
    privateLinkServiceConnections: [
      {
        name: 'cosmos'
        properties: { privateLinkServiceId: cosmosAccountId, groupIds: ['Sql'] }
      }
    ]
  }
}

resource cosmosDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: cosmosEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{ name: 'documents', properties: { privateDnsZoneId: dnsZone.id } }]
  }
}

output appSubnetId string = vnet.properties.subnets[0].id

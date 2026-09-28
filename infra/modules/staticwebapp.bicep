// Static site on the Free plan. Content is deployed from CI with a short-lived deployment token,
// not through a portal-linked repository. The Free plan cannot incur charges.
param location string
param namePrefix string
param tags object

resource site 'Microsoft.Web/staticSites@2024-04-01' = {
  name: 'stapp-${namePrefix}'
  location: location
  tags: tags
  sku: { name: 'Free', tier: 'Free' }
  properties: {}
}

output name string = site.name
output defaultHostname string = site.properties.defaultHostname

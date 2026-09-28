// Static site on the Free plan, which cannot incur charges. CI deploys the content with the site's
// deployment token, which it reads at run time through its OIDC login; the token is never stored in GitHub.
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

# 7. Private networking as a tested, optional variant

- Status: accepted
- Date: 2026-09-29

## Context

Enterprise Azure environments usually require that data services are unreachable from the internet. For a
visitor counter the hourly cost of private endpoints is not justified, which is why production uses public
endpoints protected by Entra-only access (ADR 2). The design should still show that the workload can run
fully private, and that this was tested rather than assumed.

## Decision

- `privateNetworking` in the parameter file switches the variant on (`infra/modules/network.bicep`):
  - a virtual network with a subnet delegated to `Microsoft.App/environments` for Flex Consumption VNet
    integration and a subnet for private endpoints,
  - a private endpoint for Cosmos DB and the `privatelink.documents.azure.com` private DNS zone linked to the VNet,
  - Cosmos DB with `publicNetworkAccess: Disabled`,
  - one NSG per subnet that denies outbound SSH and RDP; the endpoint subnet has default outbound access disabled.
- Host storage stays on its public endpoint (RBAC only, shared keys disabled), because Flex Consumption deploys
  the code package through it. Making it private too would need a private endpoint for blob storage and a
  deployment path from inside the network.
- The variant is verified by deploying it to a throwaway resource group
  (`infra/environments/private-network-test.bicepparam`), testing it, and deleting the resource group. PSRule for
  Azure checks it on every CI run together with the other environments.

## Consequences

- Production stays cheap; the private variant is one parameter away and has been exercised end to end
  (see docs/verification.md).
- The app subnet keeps default outbound access (Entra ID, host storage, Application Insights). Removing it would
  require a NAT gateway; PSRule's `Azure.VNET.PrivateSubnet` is excluded with that reason.

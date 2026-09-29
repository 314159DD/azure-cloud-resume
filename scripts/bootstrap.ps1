<#
.SYNOPSIS
  One-time setup with an Owner login (az login). Afterwards only GitHub Actions deploys.

.DESCRIPTION
  Creates everything the pipeline must not be able to create or change itself:

  - the resource group,
  - a deploy identity, trusted only for the GitHub environment being set up, with Contributor plus a
    Role Based Access Control Administrator assignment that an ABAC condition limits to the roles the
    templates assign (without it the pipeline could make itself Owner),
  - Azure Policy assignments that deny re-enabling key-based access on Storage, Cosmos DB and
    Application Insights. Contributor cannot remove policy assignments, so the pipeline cannot
    weaken the identity-only design.

  Run once per environment; each gets its own resource group, identity and OIDC subject:
    ./bootstrap.ps1 -Environment production -ResourceGroup rg-cloudresume
    ./bootstrap.ps1 -Environment staging    -ResourceGroup rg-cloudresume-staging
    ./bootstrap.ps1 -Environment network-test -ResourceGroup rg-cloudresume-nettest
    ./bootstrap.ps1 -Environment test -ResourceGroup <throwaway-rg> -SkipGitHubIdentity   # manual experiments

  Idempotent: safe to run again, e.g. after the list of allowed roles changes.
#>
param(
  [string]$Environment = 'production',
  [string]$ResourceGroup = 'rg-cloudresume',
  [string]$Location = 'germanywestcentral',
  [string]$GitHubRepo = '314159DD/azure-cloud-resume',
  [string]$AppName = $(if ($Environment -eq 'production') { 'gh-azure-cloud-resume' } else { "gh-azure-cloud-resume-$Environment" }),
  # For throwaway resource groups deployed by a person: no pipeline identity, but providers, role scope and policies.
  [switch]$SkipGitHubIdentity
)
# Native az calls are checked via exit codes: Windows PowerShell 5.1 turns harmless stderr warnings
# into terminating errors when ErrorActionPreference is 'Stop'.
$ErrorActionPreference = 'Continue'
function Invoke-Az {
  $output = & az @args --only-show-errors
  if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed with exit code $LASTEXITCODE" }
  $output
}
# Out-String before ConvertFrom-Json: Windows PowerShell 5.1 parses line by line otherwise.
function Invoke-AzJson { Invoke-Az @args -o json | Out-String | ConvertFrom-Json }

function Set-GitHubIdentity([string]$Name, [string]$Subject) {
  # Entra application + service principal, trusted for exactly one GitHub OIDC subject.
  $appId = Invoke-Az ad app list --display-name $Name --query '[0].appId' -o tsv
  if (-not $appId) { $appId = Invoke-Az ad app create --display-name $Name --query appId -o tsv }
  $spId = Invoke-Az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv
  if (-not $spId) { $spId = Invoke-Az ad sp create --id $appId --query id -o tsv }

  $existing = Invoke-AzJson ad app federated-credential list --id $appId
  foreach ($cred in $existing) {
    if ($cred.subject -ne $Subject) {
      Invoke-Az ad app federated-credential delete --id $appId --federated-credential-id $cred.id | Out-Null
    }
  }
  if (-not ($existing | Where-Object { $_.subject -eq $Subject })) {
    $file = New-TemporaryFile
    @{ name = 'github'; issuer = 'https://token.actions.githubusercontent.com'; subject = $Subject;
       audiences = @('api://AzureADTokenExchange') } | ConvertTo-Json | Set-Content $file -Encoding utf8
    Invoke-Az ad app federated-credential create --id $appId --parameters "@$file" -o none
    Remove-Item $file
  }
  [pscustomobject]@{ AppId = $appId; SpId = $spId }
}

$subscriptionId = Invoke-Az account show --query id -o tsv
$tenantId = Invoke-Az account show --query tenantId -o tsv
Write-Host "Subscription $subscriptionId, tenant $tenantId"

# 1) Resource providers. New subscriptions must register them once; the pipeline cannot (subscription scope).
foreach ($ns in 'Microsoft.Web', 'Microsoft.DocumentDB', 'Microsoft.Storage', 'Microsoft.Insights',
                'Microsoft.OperationalInsights', 'Microsoft.ManagedIdentity', 'Microsoft.Consumption',
                'Microsoft.Logic', 'Microsoft.AlertsManagement', 'Microsoft.PolicyInsights',
                'Microsoft.Network', 'Microsoft.App') { # Microsoft.App: Flex Consumption VNet integration
  Invoke-Az provider register --namespace $ns | Out-Null
}

# 2) Resource group: the boundary for access, cost and teardown. Its location only holds metadata;
#    the templates choose the region of each resource.
if ((Invoke-Az group exists -n $ResourceGroup) -ne 'true') {
  Invoke-Az group create -n $ResourceGroup -l $Location --tags project=cloudresume owner=steven environment=$Environment -o none
}
$rgId = Invoke-Az group show -n $ResourceGroup --query id -o tsv

# 3) Custom role for the kill switch: read, stop and start a web/function app, nothing else. Built-in roles
#    such as Website Contributor would also allow changing settings and deploying code. The ID is fixed
#    because the templates reference it (see infra/modules/killswitch.bicep). One definition serves every
#    environment; each resource group is added to its assignable scopes.
$stopperRoleId = 'a9567326-3f0c-4ec2-a9c0-8af4236ffe24'
$roleUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions/${stopperRoleId}?api-version=2022-04-01"
$existingRole = & az rest --method get --url $roleUrl --only-show-errors 2>$null | Out-String | ConvertFrom-Json
$scopes = @(@($existingRole.properties.assignableScopes) + $rgId | Where-Object { $_ } | Sort-Object -Unique)
$stopperRole = @{
  properties = @{
    roleName         = 'Cloud Resume Function Stopper'
    description      = 'Can stop and start the function app. Used by the cost kill switch.'
    type             = 'CustomRole'
    permissions      = @(@{
      actions    = @('Microsoft.Web/sites/read', 'Microsoft.Web/sites/stop/action', 'Microsoft.Web/sites/start/action')
      notActions = @()
    })
    assignableScopes = $scopes
  }
}
$roleFile = New-TemporaryFile
$stopperRole | ConvertTo-Json -Depth 5 | Set-Content $roleFile -Encoding utf8
Invoke-Az rest --method put --body "@$roleFile" --url $roleUrl -o none
Remove-Item $roleFile

# 4) Deploy identity for this environment's GitHub environment only.
#    GitHub issues subjects with immutable owner and repository IDs ("repo:owner@123/name@456:..."), so a
#    repository deleted and recreated under the same name does not inherit the trust.
if (-not $SkipGitHubIdentity) {
$repoInfo = Invoke-RestMethod "https://api.github.com/repos/$GitHubRepo"
$subjectRepo = "$($repoInfo.owner.login)@$($repoInfo.owner.id)/$($repoInfo.name)@$($repoInfo.id)"
$deploy = Set-GitHubIdentity $AppName "repo:${subjectRepo}:environment:${Environment}"

$assignableRoles = @(
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b', # Storage Blob Data Owner       (function -> host storage)
  '3913510d-42f4-4e42-8a64-420c390055eb', # Monitoring Metrics Publisher  (function -> App Insights)
  $stopperRoleId                          # Cloud Resume Function Stopper (kill switch -> stop function)
) -join ', '
$condition = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR " +
  "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$assignableRoles})) AND " +
  "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR " +
  "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$assignableRoles}))"

Invoke-Az role assignment create --assignee-object-id $deploy.SpId --assignee-principal-type ServicePrincipal `
  --role Contributor --scope $rgId -o none

# Replace the constrained RBAC admin assignment if its condition changed (compared without whitespace,
# in case Azure normalizes the stored text).
$rbacAdmin = 'Role Based Access Control Administrator'
$normalize = { param($s) ($s -replace '\s', '').ToLowerInvariant() }
$current = Invoke-AzJson role assignment list --assignee $deploy.SpId --role $rbacAdmin --scope $rgId --query '[0].{id:id,condition:condition}'
if ($current -and (& $normalize $current.condition) -ne (& $normalize $condition)) {
  Invoke-Az role assignment delete --ids $current.id -o none
  $current = $null
}
if (-not $current) {
  Invoke-Az role assignment create --assignee-object-id $deploy.SpId --assignee-principal-type ServicePrincipal `
    --role $rbacAdmin --scope $rgId --condition $condition --condition-version '2.0' -o none
}
}

# Pull requests get no Azure identity at all. ARM authorizes what-if like a deployment (write permission on
# every resource in the template), so an identity that can preview a PR could also deploy from it.

# 5) Policies: deny re-enabling key-based access. Contributor cannot delete policy assignments.
$policies = @{
  'deny-storage-shared-key'    = '8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54' # Storage accounts should prevent shared key access
  'deny-cosmos-local-auth'     = '5450f5bd-9c72-4390-a9c4-a7aba4edfdd2' # Cosmos DB accounts should have local authentication disabled
  'deny-appinsights-local-auth' = '199d5677-e4d9-4264-9465-efe1839c06bd' # Application Insights should block non-Entra ingestion
}
foreach ($name in $policies.Keys) {
  Invoke-Az policy assignment create --name $name --scope $rgId --policy $policies[$name] `
    --params '{\"effect\":{\"value\":\"Deny\"}}' -o none
}

Write-Host ''
if ($SkipGitHubIdentity) {
  Write-Host "Done. $ResourceGroup is prepared for a manual deployment (no pipeline identity)."
} else {
  Write-Host "Done. Set these on the GitHub environment '$Environment' (identifiers, not credentials):"
  Write-Host "  AZURE_CLIENT_ID      = $($deploy.AppId)"
  Write-Host "  AZURE_RESOURCE_GROUP = $ResourceGroup"
  Write-Host 'and once as repository variables:'
  Write-Host "  AZURE_TENANT_ID       = $tenantId"
  Write-Host "  AZURE_SUBSCRIPTION_ID = $subscriptionId"
}

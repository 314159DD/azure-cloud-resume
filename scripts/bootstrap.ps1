<#
.SYNOPSIS
  One-time setup with an Owner login (az login). Afterwards only GitHub Actions deploys.

.DESCRIPTION
  Creates everything the pipeline must not be able to create or change itself:

  - the resource group,
  - a deploy identity, trusted only for the GitHub "production" environment, with Contributor plus a
    Role Based Access Control Administrator assignment that an ABAC condition limits to the roles the
    templates assign (without it the pipeline could make itself Owner),
  - Azure Policy assignments that deny re-enabling key-based access on Storage, Cosmos DB and
    Application Insights. Contributor cannot remove policy assignments, so the pipeline cannot
    weaken the identity-only design.

  Idempotent: safe to run again, e.g. after the list of allowed roles changes.
#>
param(
  [string]$Location = 'germanywestcentral',
  [string]$ResourceGroup = 'rg-cloudresume',
  [string]$GitHubRepo = '314159DD/azure-cloud-resume',
  [string]$AppName = 'gh-azure-cloud-resume',
  [string]$Environment = 'production'
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
                'Microsoft.Logic', 'Microsoft.AlertsManagement', 'Microsoft.PolicyInsights') {
  Invoke-Az provider register --namespace $ns | Out-Null
}

# 2) Resource group: the boundary for access, cost and teardown. Its location only holds metadata;
#    the templates choose the region of each resource.
if ((Invoke-Az group exists -n $ResourceGroup) -ne 'true') {
  Invoke-Az group create -n $ResourceGroup -l $Location --tags project=cloudresume owner=steven -o none
}
$rgId = Invoke-Az group show -n $ResourceGroup --query id -o tsv

# 3) Deploy identity: GitHub "production" environment only.
#    GitHub issues subjects with immutable owner and repository IDs ("repo:owner@123/name@456:..."), so a
#    repository deleted and recreated under the same name does not inherit the trust.
$repoInfo = Invoke-RestMethod "https://api.github.com/repos/$GitHubRepo"
$subjectRepo = "$($repoInfo.owner.login)@$($repoInfo.owner.id)/$($repoInfo.name)@$($repoInfo.id)"
$deploy = Set-GitHubIdentity $AppName "repo:${subjectRepo}:environment:${Environment}"

$assignableRoles = @(
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b', # Storage Blob Data Owner      (function -> host storage)
  '3913510d-42f4-4e42-8a64-420c390055eb', # Monitoring Metrics Publisher (function -> App Insights)
  'de139f84-1756-47ae-9be6-808fbbe84772'  # Website Contributor          (kill switch -> stop function)
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

# Pull requests get no Azure identity at all. ARM authorizes what-if like a deployment (write permission on
# every resource in the template), so an identity that can preview a PR could also deploy from it.

# 4) Policies: deny re-enabling key-based access. Contributor cannot delete policy assignments.
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
Write-Host 'Done. Set these as GitHub Actions variables (identifiers, not credentials):'
Write-Host "  AZURE_CLIENT_ID       = $($deploy.AppId)"
Write-Host "  AZURE_TENANT_ID       = $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID = $subscriptionId"
Write-Host "  AZURE_RESOURCE_GROUP  = $ResourceGroup"

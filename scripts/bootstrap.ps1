<#
.SYNOPSIS
  One-time setup with an Owner login (az login). Afterwards only GitHub Actions deploys.

.DESCRIPTION
  Creates the resource group, an Entra application that GitHub Actions signs in as via OIDC
  (no client secret), and role assignments scoped to the resource group only:
    - Contributor: create and change resources, but not grant access.
    - Role Based Access Control Administrator, constrained by an ABAC condition to exactly the
      roles the Bicep templates assign. Without the condition the pipeline could grant itself
      Owner (privilege escalation).
  Idempotent: safe to run again, e.g. after the list of allowed roles changes.
#>
param(
  [string]$Location = 'westeurope',
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

$subscriptionId = Invoke-Az account show --query id -o tsv
$tenantId = Invoke-Az account show --query tenantId -o tsv
Write-Host "Subscription $subscriptionId, tenant $tenantId"

# 1) Resource providers. New subscriptions must register them once; the pipeline is not allowed to
#    (subscription scope).
foreach ($ns in 'Microsoft.Web', 'Microsoft.DocumentDB', 'Microsoft.Storage', 'Microsoft.Insights',
                'Microsoft.OperationalInsights', 'Microsoft.ManagedIdentity', 'Microsoft.Consumption',
                'Microsoft.Logic', 'Microsoft.AlertsManagement') {
  Invoke-Az provider register --namespace $ns | Out-Null
}

# 2) Resource group: the boundary for access, cost and teardown.
Invoke-Az group create -n $ResourceGroup -l $Location --tags project=cloudresume owner=steven -o none
$rgId = Invoke-Az group show -n $ResourceGroup --query id -o tsv

# 3) Entra application + service principal: the identity GitHub Actions uses in Azure.
$appId = Invoke-Az ad app list --display-name $AppName --query '[0].appId' -o tsv
if (-not $appId) { $appId = Invoke-Az ad app create --display-name $AppName --query appId -o tsv }
$spId = Invoke-Az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv
if (-not $spId) { $spId = Invoke-Az ad sp create --id $appId --query id -o tsv }

# 4) Federated credentials: Azure trusts tokens GitHub issues for exactly these subjects.
#    Deployments run in the "production" environment, what-if runs on pull requests. Any other
#    subject (e.g. from an earlier setup) is removed so the trust stays minimal.
$wanted = @{
  "repo:${GitHubRepo}:environment:${Environment}" = 'github-environment-production'
  "repo:${GitHubRepo}:pull_request"               = 'github-pull-request'
}
# Out-String + assignment (not @()) because Windows PowerShell 5.1 would nest the parsed array.
$existing = Invoke-Az ad app federated-credential list --id $appId -o json | Out-String | ConvertFrom-Json
foreach ($cred in $existing) {
  if (-not $wanted.ContainsKey($cred.subject)) {
    Invoke-Az ad app federated-credential delete --id $appId --federated-credential-id $cred.id | Out-Null
  }
}
foreach ($subject in $wanted.Keys) {
  if (-not ($existing | Where-Object { $_.subject -eq $subject })) {
    $file = New-TemporaryFile
    @{ name = $wanted[$subject]; issuer = 'https://token.actions.githubusercontent.com'; subject = $subject;
       audiences = @('api://AzureADTokenExchange') } | ConvertTo-Json | Set-Content $file -Encoding utf8
    Invoke-Az ad app federated-credential create --id $appId --parameters "@$file" -o none
    Remove-Item $file
  }
}

# 5) Role assignments on the resource group only.
$assignableRoles = @(
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b', # Storage Blob Data Owner      (function -> host storage)
  '3913510d-42f4-4e42-8a64-420c390055eb', # Monitoring Metrics Publisher (function -> App Insights)
  'de139f84-1756-47ae-9be6-808fbbe84772'  # Website Contributor          (kill switch -> stop function)
) -join ', '
$condition = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR " +
  "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$assignableRoles})) AND " +
  "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR " +
  "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$assignableRoles}))"

Invoke-Az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal `
  --role Contributor --scope $rgId -o none

# Replace the constrained RBAC admin assignment if its condition is outdated.
$rbacAdmin = 'Role Based Access Control Administrator'
$current = Invoke-Az role assignment list --assignee $spId --role $rbacAdmin --scope $rgId --query '[0].{id:id,condition:condition}' -o json | Out-String | ConvertFrom-Json
if ($current -and $current.condition -ne $condition) {
  Invoke-Az role assignment delete --ids $current.id -o none
  $current = $null
}
if (-not $current) {
  Invoke-Az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal `
    --role $rbacAdmin --scope $rgId --condition $condition --condition-version '2.0' -o none
}

Write-Host ''
Write-Host 'Done. Set these as GitHub Actions *variables* (they are identifiers, not secrets):'
Write-Host "  AZURE_CLIENT_ID       = $appId"
Write-Host "  AZURE_TENANT_ID       = $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID = $subscriptionId"

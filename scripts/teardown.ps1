<#
.SYNOPSIS
  Deletes everything this project created in Azure. Nothing keeps running or billing afterwards.
.DESCRIPTION
  Removes the resource group (all resources, role assignments scoped to it, the budget) and, with
  -IncludeIdentity, the Entra application used by GitHub Actions. Redeploying later needs the bootstrap again.
#>
param(
  [string]$ResourceGroup = 'rg-cloudresume',
  [string]$AppName = 'gh-azure-cloud-resume',
  [switch]$IncludeIdentity
)
$ErrorActionPreference = 'Continue'

az group delete --name $ResourceGroup --yes --only-show-errors
if ($LASTEXITCODE -ne 0) { throw "Deleting $ResourceGroup failed" }

if ($IncludeIdentity) {
  $appId = az ad app list --display-name $AppName --query '[0].appId' -o tsv --only-show-errors
  if ($appId) { az ad app delete --id $appId --only-show-errors }
}
Write-Host "Deleted $ResourceGroup$(if ($IncludeIdentity) { " and $AppName" })."

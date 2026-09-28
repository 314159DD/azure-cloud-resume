#!/usr/bin/env bash
# Checks, as the identity that is signed in (in CI: the deploy identity), that the guardrails hold.
# Every check attempts a change that must be refused, so nothing is modified when they pass:
#   1. turning on shared-key access on the storage account  -> denied by Azure Policy
#   2. turning on local (key) auth on Cosmos DB              -> denied by Azure Policy
#   3. granting itself Owner on the resource group           -> denied by the ABAC condition
#   4. key-based access and publishing credentials are off in the live configuration
set -euo pipefail

RG="${1:?usage: verify-guardrails.sh <resource-group>}"
failures=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

# Runs a command that must be refused and checks the reason. Prints the reason code on success.
expect_refused() {
  local label="$1" reason="$2"; shift 2
  local output
  if output=$("$@" 2>&1); then
    fail "$label was allowed"
  elif grep -q "$reason" <<< "$output"; then
    pass "$label refused ($reason)"
  else
    fail "$label failed for an unexpected reason: $(head -c 300 <<< "$output")"
  fi
}

storage=$(az storage account list -g "$RG" --query "[0].name" -o tsv)
cosmos=$(az cosmosdb list -g "$RG" --query "[0].name" -o tsv)
func=$(az functionapp list -g "$RG" --query "[0].name" -o tsv)
rg_id=$(az group show -n "$RG" --query id -o tsv)

# Identity of the signed-in principal, read from the token so no directory permission is needed.
claims=$(az account get-access-token --query accessToken -o tsv | cut -d. -f2 | tr '_-' '/+' \
  | awk '{ while (length($0) % 4) $0 = $0 "="; print }' | base64 -d 2>/dev/null)
oid=$(jq -r .oid <<< "$claims")
is_app=$([[ "$(jq -r '.idtyp // empty' <<< "$claims")" == "app" ]] && echo true || echo false)

expect_refused "enabling shared-key access on $storage" RequestDisallowedByPolicy \
  az storage account update -g "$RG" -n "$storage" --allow-shared-key-access true -o none

expect_refused "enabling local auth on $cosmos" RequestDisallowedByPolicy \
  az resource update -g "$RG" -n "$cosmos" --resource-type Microsoft.DocumentDB/databaseAccounts \
    --set properties.disableLocalAuth=false -o none

# Only meaningful for the pipeline identity: a human Owner running this locally could actually grant it.
if [[ "$is_app" == "true" ]]; then
  expect_refused "granting Owner to the signed-in identity" AuthorizationFailed \
    az role assignment create --assignee-object-id "$oid" --assignee-principal-type ServicePrincipal \
      --role Owner --scope "$rg_id" -o none
else
  echo "SKIP: Owner self-assignment check (signed in as a user, run it as the pipeline identity)"
fi

[[ "$(az storage account show -g "$RG" -n "$storage" --query allowSharedKeyAccess -o tsv)" == "false" ]] \
  && pass "storage shared-key access is off" || fail "storage shared-key access is on"
[[ "$(az cosmosdb show -g "$RG" -n "$cosmos" --query disableLocalAuth -o tsv)" == "true" ]] \
  && pass "Cosmos DB local auth is off" || fail "Cosmos DB local auth is on"
func_id=$(az functionapp show -g "$RG" -n "$func" --query id -o tsv)
for kind in ftp scm; do
  allowed=$(az rest --method get --query properties.allow -o tsv \
    --url "https://management.azure.com${func_id}/basicPublishingCredentialsPolicies/${kind}?api-version=2024-04-01")
  [[ "$allowed" == "false" ]] && pass "$kind basic publishing credentials are off" || fail "$kind basic publishing credentials are on"
done

echo
(( failures == 0 )) && echo "All guardrail checks passed." || { echo "$failures check(s) failed."; exit 1; }

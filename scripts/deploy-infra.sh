#!/usr/bin/env bash
# Runs `az deployment group create` and retries only on transient platform errors seen in this project:
#   - "principal ID ... was not found in the AAD tenant": a newly created managed identity has not
#     replicated to Cosmos DB yet (Entra ID is eventually consistent).
#   - "operation in progress which requires exclusive lock": Cosmos DB is still busy with an earlier change.
# Any other failure stops immediately. Prints the deployment outputs as JSON on success.
#
#   scripts/deploy-infra.sh <resource-group> <deployment-name> <parameter-file>
set -euo pipefail

RG="${1:?usage: deploy-infra.sh <resource-group> <deployment-name> <parameter-file>}"
NAME="${2:?}"
PARAMETERS="${3:?}"
ATTEMPTS=4
WAIT_SECONDS=60
TRANSIENT='was not found in the AAD tenant|requires exclusive lock'

for attempt in $(seq 1 "$ATTEMPTS"); do
  if outputs=$(az deployment group create --resource-group "$RG" --name "$NAME" \
      --template-file infra/main.bicep --parameters "$PARAMETERS" \
      --query properties.outputs --output json 2> deploy-error.log); then
    echo "$outputs"
    exit 0
  fi
  if (( attempt < ATTEMPTS )) && grep -qE "$TRANSIENT" deploy-error.log; then
    echo "::warning::transient deployment error on attempt $attempt, retrying in ${WAIT_SECONDS}s: $(grep -oE "$TRANSIENT" deploy-error.log | head -1)" >&2
    sleep "$WAIT_SECONDS"
    continue
  fi
  cat deploy-error.log >&2
  exit 1
done

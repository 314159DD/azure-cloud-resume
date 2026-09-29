#!/usr/bin/env bash
# GitHub side of the setup, as code: environments, their branch policies and reviewers, the variables the
# workflows read, and branch protection for main. Idempotent; run it after scripts/bootstrap.ps1 with the
# client ids that script printed. Needs `gh` authenticated as a repository admin.
#
#   scripts/configure-github.sh <owner/repo> <staging-client-id> <production-client-id> <network-test-client-id>
#                               <tenant-id> <subscription-id> <reviewer-login>
#   SKIP_BRANCH_PROTECTION=true leaves branch protection unchanged.
#   (BUDGET_ALERT_EMAIL is set separately as a secret: gh secret set BUDGET_ALERT_EMAIL -R <owner/repo>)
set -euo pipefail

REPO="${1:?usage: see header}"
STAGING_CLIENT_ID="${2:?}"
PRODUCTION_CLIENT_ID="${3:?}"
NETWORK_TEST_CLIENT_ID="${4:?}"
TENANT_ID="${5:?}"
SUBSCRIPTION_ID="${6:?}"
REVIEWER="${7:?}"
SKIP_BRANCH_PROTECTION="${SKIP_BRANCH_PROTECTION:-false}"
REVIEWER_ID=$(gh api "users/$REVIEWER" --jq .id)

# Environments: all deploy only from main; production and the (billed) network test also wait for a reviewer.
configure_environment() {
  local name="$1" reviewers="$2" client_id="$3" resource_group="$4"
  gh api -X PUT "repos/$REPO/environments/$name" --silent --input - <<EOF
{"reviewers": $reviewers,
 "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
  gh api "repos/$REPO/environments/$name/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx main \
    || gh api -X POST "repos/$REPO/environments/$name/deployment-branch-policies" -f name=main --silent
  gh variable set AZURE_CLIENT_ID -R "$REPO" --env "$name" -b "$client_id"
  gh variable set AZURE_RESOURCE_GROUP -R "$REPO" --env "$name" -b "$resource_group"
  echo "environment $name: branch main, reviewers $reviewers, resource group $resource_group"
}
configure_environment staging '[]' "$STAGING_CLIENT_ID" rg-cloudresume-staging
configure_environment production "[{\"type\":\"User\",\"id\":$REVIEWER_ID}]" "$PRODUCTION_CLIENT_ID" rg-cloudresume
configure_environment network-test "[{\"type\":\"User\",\"id\":$REVIEWER_ID}]" "$NETWORK_TEST_CLIENT_ID" rg-cloudresume-nettest

gh variable set AZURE_TENANT_ID -R "$REPO" -b "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID -R "$REPO" -b "$SUBSCRIPTION_ID"

# main: changes only through pull requests whose CI is green, for administrators too; no force pushes.
[[ "$SKIP_BRANCH_PROTECTION" == "true" ]] && { echo "branch protection skipped"; exit 0; }
gh api -X PUT "repos/$REPO/branches/main/protection" --silent --input - <<'EOF'
{
  "required_status_checks": {
    "strict": false,
    "contexts": [
      "API (lint, typecheck, test)",
      "API integration (Cosmos DB emulator)",
      "Infrastructure (Bicep, PSRule for Azure)",
      "analyze"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
echo "branch protection on main: pull requests with green CI required, enforced for admins"

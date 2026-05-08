#!/usr/bin/env bash
# Configure the app-store-release GitHub Environment for an iOS repo.
#
# Requires: gh CLI authenticated as a repo admin (personal token, not bot token).
# The automation bot does not have environment-write permissions.
#
# Usage:
#   ./scripts/ci/bootstrap-release-env.sh <org/repo> [reviewer_login ...]
#
# Examples:
#   ./scripts/ci/bootstrap-release-env.sh RiddimSoftware/bap sunnypurewal
#   ./scripts/ci/bootstrap-release-env.sh RiddimSoftware/sonnio sunnypurewal
#
# What it does:
#   1. Creates (or updates) the 'app-store-release' environment.
#   2. Adds required_reviewers protection with prevent_self_review.
#   3. Prints the resulting protection config for verification.
#
# GitHub plan note: required_reviewers and prevent_self_review are available
# on GitHub Team and Enterprise plans for private repos. Public repos always
# support environment protection. If the API returns 422, check the plan.
set -euo pipefail

REPO="${1:?Usage: $0 <org/repo> [reviewer_login ...]}"
shift
REVIEWERS=("${@:-sunnypurewal}")
ENV_NAME="app-store-release"

echo "Resolving reviewer IDs..."
reviewer_json="["
sep=""
for login in "${REVIEWERS[@]}"; do
  id=$(gh api "users/${login}" --jq '.id')
  echo "  ${login} -> ${id}"
  reviewer_json+="${sep}{\"type\":\"User\",\"id\":${id}}"
  sep=","
done
reviewer_json+="]"

echo ""
echo "Configuring environment '${ENV_NAME}' for ${REPO}..."
result=$(gh api --method PUT "repos/${REPO}/environments/${ENV_NAME}" \
  --field prevent_self_review=true \
  --field "reviewers=${reviewer_json}")

echo ""
echo "Result:"
echo "${result}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f\"  name: {d['name']}\")
print(f\"  can_admins_bypass: {d['can_admins_bypass']}\")
for r in d.get('protection_rules', []):
    print(f\"  rule type: {r['type']}\")
    if 'prevent_self_review' in r:
        print(f\"  prevent_self_review: {r['prevent_self_review']}\")
    for rv in r.get('reviewers', []):
        print(f\"  reviewer: {rv['reviewer']['login']}\")
"

echo ""
echo "Done. Verify at: https://github.com/${REPO}/settings/environments"

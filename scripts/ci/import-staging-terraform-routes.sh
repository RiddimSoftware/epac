#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT="${REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TERRAFORM_DIR="${TERRAFORM_DIR:-${REPOSITORY_ROOT}/infra/terraform/staging}"
MANIFEST_PATH="${MANIFEST_PATH:-${REPOSITORY_ROOT}/backend/manifest/deployment-services.json}"
ENV_NAME="${ENV_NAME:-staging}"
API_ID="${API_ID:-}"
REGION="${AWS_REGION:-}"
DRY_RUN="${DRY_RUN:-false}"

if [ "${ENV_NAME}" != "staging" ]; then
  echo "Unsupported ENV_NAME=${ENV_NAME}; expected staging." >&2
  exit 1
fi

if [ ! -d "${TERRAFORM_DIR}" ]; then
  echo "Terraform directory not found: ${TERRAFORM_DIR}" >&2
  exit 1
fi

if [ ! -f "${MANIFEST_PATH}" ]; then
  echo "Manifest file not found: ${MANIFEST_PATH}" >&2
  exit 1
fi

terraform_var() {
  local expression="$1"
  terraform -chdir="${TERRAFORM_DIR}" console -no-color <<<"${expression}" | tr -d '"'
}

if [ -z "${API_ID}" ] || [ "${API_ID}" = "None" ]; then
  API_ID="$(terraform_var "var.apigw_api_id")"
fi

if [ -z "${REGION}" ] || [ "${REGION}" = "None" ]; then
  REGION="$(terraform_var "var.aws_region")"
fi

if [ -z "${API_ID}" ] || [ "${API_ID}" = "None" ]; then
  echo "Unable to resolve staging API ID." >&2
  exit 1
fi

if [ -z "${REGION}" ] || [ "${REGION}" = "None" ]; then
  echo "Unable to resolve AWS region." >&2
  exit 1
fi

dry_run=false
case "${DRY_RUN}" in
  1|true|TRUE|yes|YES)
    dry_run=true
    ;;
esac

routes_json="$(aws apigatewayv2 get-routes --api-id "${API_ID}" --region "${REGION}" --output json)"
state_list="$(terraform -chdir="${TERRAFORM_DIR}" state list)"
imported_count=0
missing_count=0
managed_count=0

while IFS=$'\t' read -r service route_key; do
  [ -z "${service}" ] && continue

  address="aws_apigatewayv2_route.staging[\"${service}::${route_key}\"]"

  if grep -Fxq "${address}" <<<"${state_list}"; then
    managed_count=$((managed_count + 1))
    continue
  fi

  route_id="$(printf '%s' "${routes_json}" | jq -r --arg route_key "${route_key}" '.Items[]? | select(.RouteKey == $route_key) | .RouteId' | head -n 1)"

  if [ -z "${route_id}" ] || [ "${route_id}" = "null" ] || [ "${route_id}" = "None" ]; then
    echo "No existing API Gateway route found for ${route_key}; Terraform apply will create it."
    missing_count=$((missing_count + 1))
    continue
  fi

  import_id="${API_ID}/${route_id}"
  if [ "${dry_run}" = true ]; then
    echo "Would import ${route_key} into ${address} from ${import_id}."
  else
    echo "Importing ${route_key} into ${address} from ${import_id}."
    terraform -chdir="${TERRAFORM_DIR}" import -input=false "${address}" "${import_id}"
  fi
  imported_count=$((imported_count + 1))
done < <(jq -r --arg env "${ENV_NAME}" '.services[] | select(.http != null and .deploy[$env] == true) | .name as $service | .http.routes[$env][]? | [$service, (.method + " " + .path)] | @tsv' "${MANIFEST_PATH}")

if [ "${dry_run}" = true ]; then
  echo "Dry run complete: ${managed_count} routes already managed, ${imported_count} routes would be imported, ${missing_count} routes missing in AWS."
else
  echo "Import complete: ${managed_count} routes already managed, ${imported_count} routes imported, ${missing_count} routes missing in AWS."
fi

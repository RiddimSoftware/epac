#!/usr/bin/env bash

set -euo pipefail

API_NAME="${API_NAME:-epac-api-staging}"
ENV_NAME="${ENV_NAME:-staging}"
STAGE_NAME="${STAGE_NAME:-staging}"
REGION="${AWS_REGION:-us-east-1}"
API_ID="${API_ID:-}"
REPOSITORY_ROOT="${REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MANIFEST_PATH="${MANIFEST_PATH:-${REPOSITORY_ROOT}/backend/manifest/deployment-services.json}"
DOMAIN_NAME="${DOMAIN_NAME:-}"

target_env="${ENV_NAME}"
if [ "$target_env" != "staging" ] && [ "$target_env" != "production" ]; then
  echo "Unsupported ENV_NAME=${target_env}; expected staging or production." >&2
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

remove_permission_statement() {
  local function_name="$1"
  local statement_id="$2"
  aws lambda remove-permission \
    --region "${REGION}" \
    --function-name "${function_name}" \
    --statement-id "${statement_id}" \
    >/dev/null 2>&1 || true
}

remove_matching_invoke_permissions() {
  local function_name="$1"
  local statement_prefix="$2"
  local policy

  if ! policy=$(aws lambda get-policy --region "${REGION}" --function-name "${function_name}" --query Policy --output text 2>/dev/null); then
    return 0
  fi

  printf '%s\n' "${policy}" | jq -r --arg prefix "${statement_prefix}" '
    # AWS CLI may return Policy as either a JSON object or a JSON-encoded string.
    (if type == "string" then fromjson else . end)
    | .Statement[]?
    | (.Sid? // empty)
    | select(startswith($prefix))
  ' | while IFS= read -r statement_id; do
    [ -z "${statement_id}" ] && continue
    remove_permission_statement "${function_name}" "${statement_id}"
  done
}

if [ -z "${API_ID}" ] || [ "${API_ID}" = "None" ]; then
  if [ -n "${STAGING_API_BASE_URL:-}" ]; then
    DOMAIN_NAME="${STAGING_API_BASE_URL#*://}"
    DOMAIN_NAME="${DOMAIN_NAME%%/*}"
  elif [ -z "${DOMAIN_NAME}" ] && [ -n "${CUSTOM_DOMAIN:-}" ]; then
    DOMAIN_NAME="${CUSTOM_DOMAIN}"
  fi

  if [ -n "${DOMAIN_NAME}" ]; then
    if API_ID=$(aws apigatewayv2 get-api-mappings \
      --domain-name "${DOMAIN_NAME}" \
      --query "Items[?Stage=='${STAGE_NAME}'].ApiId | [0]" \
      --output text 2>/dev/null); then
      :
    else
      echo "Warning: GetApiMappings denied or failed for ${DOMAIN_NAME}; falling back to API name lookup." >&2
      API_ID="None"
    fi
  fi

  if [ -z "${API_ID}" ] || [ "${API_ID}" = "None" ]; then
    API_ID=$(aws apigatewayv2 get-apis \
      --query "Items[?Name=='${API_NAME}'].ApiId | [0]" \
      --output text)
  fi
fi

if [ -z "${API_ID}" ] || [ "${API_ID}" = "None" ]; then
  if [ -n "${API_NAME}" ]; then
    echo "API ${API_NAME} not resolved by name. Set API_ID or STAGING_API_BASE_URL correctly." >&2
  else
    echo "Unable to resolve API ID. Set API_ID or STAGING_API_BASE_URL and ensure API mappings exist." >&2
  fi
  exit 1
fi

if [ ! -f "${MANIFEST_PATH}" ]; then
  echo "Manifest file not found: ${MANIFEST_PATH}" >&2
  exit 1
fi

while IFS='|' read -r SERVICE METHOD ROUTE_KEY PAYLOAD_VERSION; do
  [ -z "${SERVICE}" ] && continue
  FUNCTION_NAME="epac-${SERVICE}-${ENV_NAME}"

  if [ "${target_env}" = "production" ]; then
    if ! aws lambda get-function --function-name "${FUNCTION_NAME}" >/dev/null 2>&1; then
      FUNCTION_NAME="${SERVICE}"
    fi
  fi

  LAMBDA_ARN=$(aws lambda get-function --function-name "${FUNCTION_NAME}" --query 'Configuration.FunctionArn' --output text)
  if [ -z "${LAMBDA_ARN}" ] || [ "${LAMBDA_ARN}" = "None" ]; then
    echo "Function ${FUNCTION_NAME} not found; skipping ${ROUTE_KEY}" >&2
    continue
  fi

  if [ "${METHOD}" = "ANY" ]; then
    INTEGRATION_ID=$(aws apigatewayv2 get-integrations \
      --api-id "${API_ID}" \
      --query "Items[?IntegrationUri=='${LAMBDA_ARN}' && IntegrationMethod=='ANY'].IntegrationId | [0]" \
      --output text)
  else
    INTEGRATION_ID=$(aws apigatewayv2 get-integrations \
      --api-id "${API_ID}" \
      --query "Items[?IntegrationUri=='${LAMBDA_ARN}'].IntegrationId | [0]" \
      --output text)
  fi

  if [ -z "${INTEGRATION_ID}" ] || [ "${INTEGRATION_ID}" = "None" ]; then
    PAYLOAD_VERSION="${PAYLOAD_VERSION:-2.0}"
    if [ "${METHOD}" = "ANY" ]; then
      INTEGRATION_ID=$(aws apigatewayv2 create-integration \
        --api-id "${API_ID}" \
        --integration-type AWS_PROXY \
        --integration-uri "${LAMBDA_ARN}" \
        --integration-method ANY \
        --payload-format-version "${PAYLOAD_VERSION}" \
        --query 'IntegrationId' \
        --output text)
    else
      INTEGRATION_ID=$(aws apigatewayv2 create-integration \
        --api-id "${API_ID}" \
        --integration-type AWS_PROXY \
        --integration-uri "${LAMBDA_ARN}" \
        --payload-format-version "${PAYLOAD_VERSION}" \
        --query 'IntegrationId' \
        --output text)
    fi
  fi

  ROUTE_ID=$(aws apigatewayv2 get-routes \
    --api-id "${API_ID}" \
    --query "Items[?RouteKey=='${ROUTE_KEY}'].RouteId | [0]" \
    --output text)

  if [ -z "${ROUTE_ID}" ] || [ "${ROUTE_ID}" = "None" ]; then
    aws apigatewayv2 create-route \
      --api-id "${API_ID}" \
      --route-key "${ROUTE_KEY}" \
      --target "integrations/${INTEGRATION_ID}" >/dev/null
  else
    aws apigatewayv2 update-route \
      --api-id "${API_ID}" \
      --route-id "${ROUTE_ID}" \
      --target "integrations/${INTEGRATION_ID}" >/dev/null
  fi

  if [ "${target_env}" = "staging" ]; then
    SOURCE_PATH="${ROUTE_KEY#* }"
    SOURCE_PATH="${SOURCE_PATH//\{id\}/*}"
    SOURCE_PATH="${SOURCE_PATH//\{org_id\}/*}"
    SOURCE_PATH="${SOURCE_PATH//\{slug\}/*}"
    SOURCE_PATH="${SOURCE_PATH//\{date\}/*}"

    STATEMENT_ID="apigateway-${SERVICE}-${ENV_NAME}"
    STATEMENT_PREFIX="apigateway-${SERVICE}-${ENV_NAME}"
    SOURCE_ARN="arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/${METHOD}${SOURCE_PATH}"
  else
    STATEMENT_ID="apigw-epac-api-${SERVICE}"
    STATEMENT_PREFIX="apigw-epac-api-"
    SOURCE_ARN="arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*"
  fi

  remove_permission_statement "${FUNCTION_NAME}" "${STATEMENT_ID}"
  remove_matching_invoke_permissions "${FUNCTION_NAME}" "${STATEMENT_PREFIX}"

  if ! aws lambda add-permission \
      --region "${REGION}" \
      --function-name "${FUNCTION_NAME}" \
      --statement-id "${STATEMENT_ID}" \
      --action lambda:InvokeFunction \
      --principal apigateway.amazonaws.com \
      --source-arn "${SOURCE_ARN}" \
      >/dev/null 2>&1; then
    aws lambda add-permission \
      --region "${REGION}" \
      --function-name "${FUNCTION_NAME}" \
      --statement-id "${STATEMENT_ID}" \
      --action lambda:InvokeFunction \
      --principal apigateway.amazonaws.com >/dev/null || true
  fi

done < <(jq -r --arg env "$target_env" '.services[] | select(.http != null and .deploy[$env] == true) | .name as $service | .http.routes[$env][] | "\($service)|\(.method)|\(.method + " " + .path)|\(.payload_format_version // "2.0")"' "$MANIFEST_PATH")

if aws apigatewayv2 get-stage --api-id "${API_ID}" --stage-name "${STAGE_NAME}" --output json >/dev/null 2>&1; then
  AUTO_DEPLOY=$(aws apigatewayv2 get-stage \
    --api-id "${API_ID}" \
    --stage-name "${STAGE_NAME}" \
    --query 'AutoDeploy' \
    --output text)

  if [ "${AUTO_DEPLOY}" != "True" ]; then
    DEPLOYMENT_ID=$(aws apigatewayv2 create-deployment \
      --api-id "${API_ID}" \
      --query 'DeploymentId' \
      --output text)

    aws apigatewayv2 update-stage \
      --api-id "${API_ID}" \
      --stage-name "${STAGE_NAME}" \
      --deployment-id "${DEPLOYMENT_ID}" >/dev/null
  else
    echo "Stage ${STAGE_NAME} has AutoDeploy=true; skipping manual deployment binding."
  fi
else
  DEPLOYMENT_ID=$(aws apigatewayv2 create-deployment \
    --api-id "${API_ID}" \
    --query 'DeploymentId' \
    --output text)

  aws apigatewayv2 create-stage \
    --api-id "${API_ID}" \
    --stage-name "${STAGE_NAME}" \
    --deployment-id "${DEPLOYMENT_ID}" >/dev/null
fi

echo "API route sync complete for ${API_ID} at stage ${STAGE_NAME}."

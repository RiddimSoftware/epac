#!/usr/bin/env bash

set -euo pipefail

API_NAME="${API_NAME:-}"
ENV_NAME="${ENV_NAME:-staging}"
STAGE_NAME="${STAGE_NAME:-staging}"
REGION="${AWS_REGION:-us-east-1}"
API_ID="${API_ID:-}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "${API_ID}" ] || [ "${API_ID}" = "None" ]; then
  if [ -n "${STAGING_API_BASE_URL:-}" ]; then
    DOMAIN_NAME="${STAGING_API_BASE_URL#*://}"
    DOMAIN_NAME="${DOMAIN_NAME%%/*}"
  elif [ -n "${DOMAIN_NAME:-}" ]; then
    DOMAIN_NAME="${DOMAIN_NAME}"
  elif [ -n "${CUSTOM_DOMAIN:-}" ]; then
    DOMAIN_NAME="${CUSTOM_DOMAIN}"
  fi

  if [ -n "${DOMAIN_NAME}" ]; then
    API_ID=$(aws apigatewayv2 get-api-mappings \
      --domain-name "${DOMAIN_NAME}" \
      --query "Items[?Stage=='${STAGE_NAME}'].ApiId | [0]" \
      --output text)
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

# Route Key | Method | Function suffix | Payload version
ROUTES=(
  "GET /health|GET|health|2.0"
  "GET /search/speeches|GET|search|2.0"
  "GET /api/v1/members/{id}/speeches|GET|member-speeches|2.0"
  "GET /api/v1/on-this-day|GET|on-this-day|2.0"
  "GET /api/v1/ridings/{slug}/boundary|GET|riding-boundary|2.0"
  "GET /api/v1/live|GET|live-status|2.0"
  "POST /api/v1/device/register|POST|device-register|2.0"
)

for route_def in "${ROUTES[@]}"; do
  IFS='|' read -r ROUTE_KEY METHOD SERVICE PAYLOAD_VERSION <<<"${route_def}"
  FUNCTION_NAME="epac-${SERVICE}-${ENV_NAME}"

  LAMBDA_ARN=$(aws lambda get-function --function-name "${FUNCTION_NAME}" --query 'Configuration.FunctionArn' --output text)
  if [ -z "${LAMBDA_ARN}" ] || [ "${LAMBDA_ARN}" = "None" ]; then
    echo "Function ${FUNCTION_NAME} not found; skipping ${ROUTE_KEY}" >&2
    continue
  fi

  INTEGRATION_ID=$(aws apigatewayv2 get-integrations \
    --api-id "${API_ID}" \
    --query "Items[?IntegrationUri=='${LAMBDA_ARN}'].IntegrationId | [0]" \
    --output text)

  if [ -z "${INTEGRATION_ID}" ] || [ "${INTEGRATION_ID}" = "None" ]; then
    INTEGRATION_ID=$(aws apigatewayv2 create-integration \
      --api-id "${API_ID}" \
      --integration-type AWS_PROXY \
      --integration-uri "${LAMBDA_ARN}" \
      --payload-format-version "${PAYLOAD_VERSION}" \
      --query 'IntegrationId' \
      --output text)
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

  SOURCE_PATH="${ROUTE_KEY#* }"
  SOURCE_PATH="${SOURCE_PATH//\{id\}/*}"
  SOURCE_PATH="${SOURCE_PATH//\{slug\}/*}"

  aws lambda add-permission \
    --function-name "${FUNCTION_NAME}" \
    --statement-id "apigateway-${SERVICE}-${ENV_NAME}" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/${METHOD}${SOURCE_PATH}" \
    >/dev/null 2>&1 || true

done

DEPLOYMENT_ID=$(aws apigatewayv2 create-deployment \
  --api-id "${API_ID}" \
  --query 'DeploymentId' \
  --output text)

if aws apigatewayv2 get-stage --api-id "${API_ID}" --stage-name "${STAGE_NAME}" >/dev/null 2>&1; then
  aws apigatewayv2 update-stage \
    --api-id "${API_ID}" \
    --stage-name "${STAGE_NAME}" \
    --deployment-id "${DEPLOYMENT_ID}" >/dev/null
else
  aws apigatewayv2 create-stage \
    --api-id "${API_ID}" \
    --stage-name "${STAGE_NAME}" \
    --deployment-id "${DEPLOYMENT_ID}" >/dev/null
fi

echo "Staging API route sync complete for ${API_ID} at stage ${STAGE_NAME}."

#!/usr/bin/env bash

set -euo pipefail

ENV_NAME="${ENV_NAME:-staging}"
REGION="${AWS_REGION:-us-east-1}"
MANIFEST_PATH="${MANIFEST_PATH:-backend/manifest/deployment-services.json}"
LAMBDA_ROLE="${LAMBDA_ROLE:-arn:aws:iam::227530433709:role/epac-lambda-role}"
API_ID="${API_ID:-}"
ACCOUNT_ID="${ACCOUNT_ID:-}"
SERVICE_FILTER="${SERVICE_FILTER:-all}"

if [ "$ENV_NAME" != "staging" ] && [ "$ENV_NAME" != "production" ]; then
  echo "Unsupported ENV_NAME=${ENV_NAME}; expected staging or production." >&2
  exit 1
fi

if [ -z "$API_ID" ]; then
  echo "API_ID is required." >&2
  exit 1
fi

if [ -z "$ACCOUNT_ID" ]; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
fi

if [ ! -f "$MANIFEST_PATH" ]; then
  echo "Manifest file not found: ${MANIFEST_PATH}" >&2
  exit 1
fi

{
  echo "## Provision ${ENV_NAME} standard S3 HTTP Lambdas"
  echo ""
  echo "| Resource | Outcome |"
  echo "|---|---|"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

while IFS= read -r service; do
  [ -z "$service" ] && continue
  if [ "$SERVICE_FILTER" != "all" ] && [ "$SERVICE_FILTER" != "$service" ]; then
    continue
  fi

  source_dir="backend/${service}"
  function_name="epac-${service}-${ENV_NAME}"

  if [ ! -f "${source_dir}/go.mod" ]; then
    echo "::error title=Missing backend service source::${source_dir}/go.mod does not exist for manifest service ${service}."
    exit 1
  fi

  if ! aws lambda get-function --function-name "$function_name" >/dev/null 2>&1; then
    aws lambda create-function \
      --function-name "$function_name" \
      --runtime provided.al2023 \
      --handler bootstrap \
      --architectures arm64 \
      --role "$LAMBDA_ROLE" \
      --zip-file fileb://infra/placeholder.zip \
      --timeout 30 \
      --memory-size 512 \
      --ephemeral-storage '{"Size":2048}' \
      >/dev/null
    aws lambda wait function-active-v2 --function-name "$function_name"
    echo "| ${function_name} | created with 30 s timeout / 512 MB / 2048 MB /tmp |" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  else
    aws lambda update-function-configuration \
      --function-name "$function_name" \
      --timeout 30 \
      --memory-size 512 \
      --ephemeral-storage '{"Size":2048}' \
      >/dev/null
    aws lambda wait function-updated --function-name "$function_name"
    echo "| ${function_name} | already existed, serving config ensured |" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  fi

  statement_id="apigw-invoke-${service}-${ENV_NAME}"
  permission_error="$(mktemp)"
  if ! aws lambda add-permission \
      --function-name "$function_name" \
      --statement-id "$statement_id" \
      --action lambda:InvokeFunction \
      --principal apigateway.amazonaws.com \
      --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*" \
      >/dev/null 2>"$permission_error"; then
    if grep -q "ResourceConflictException" "$permission_error"; then
      :
    else
      cat "$permission_error" >&2
      rm -f "$permission_error"
      exit 1
    fi
  fi
  rm -f "$permission_error"
  echo "| ${function_name} API Gateway invoke permission | ensured |" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
done < <(jq -r --arg env "$ENV_NAME" '
  .services[]
  | select(.deploy[$env] == true)
  | select(.http != null)
  | select(.sync[$env].artifact == true)
  | select(.name != "hansard-search" and .name != "lobbying")
  | .name
' "$MANIFEST_PATH")

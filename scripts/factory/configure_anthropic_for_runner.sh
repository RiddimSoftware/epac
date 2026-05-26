#!/usr/bin/env bash
set -euo pipefail

write_env_secret() {
  local name="$1"
  local value="$2"

  if [[ -z "$value" ]]; then
    return 1
  fi

  echo "::add-mask::$value"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
      echo "${name}<<EOF"
      printf '%s\n' "$value"
      echo "EOF"
    } >> "$GITHUB_ENV"
  else
    export "$name=$value"
  fi
}

normalize_secret() {
  python3 -c 'import json,sys
raw=sys.stdin.read().strip()
if not raw:
    raise SystemExit(1)
try:
    data=json.loads(raw)
except json.JSONDecodeError:
    print(raw)
else:
    for key in (
        "ANTHROPIC_API_KEY",
        "LINEAR_API_KEY",
        "api_key",
        "apiKey",
        "key",
        "token",
        "value",
        "linearApiKey",
    ):
        value=data.get(key)
        if value:
            print(value)
            break
    else:
        raise SystemExit(1)'
}

fetch_secret() {
  local secret_id="$1"
  if ! command -v aws >/dev/null 2>&1; then
    return 1
  fi
  AWS_PROFILE="${AWS_PROFILE:-riddim-agent}" aws ssm get-parameter \
    --region "${AWS_REGION:-us-east-1}" \
    --name "$secret_id" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text 2>/dev/null | normalize_secret
}

anthropic_key="${ANTHROPIC_API_KEY:-}"
if [[ -z "$anthropic_key" ]]; then
  anthropic_key="$(fetch_secret "/anthropic/api-key" || true)"
fi
if [[ -z "$anthropic_key" ]]; then
  anthropic_key="$(fetch_secret "/anthropic/claude-api-key" || true)"
fi
if [[ -z "$anthropic_key" ]]; then
  echo "ANTHROPIC_API_KEY is required; set it as a GitHub secret or provide AWS access to /anthropic/api-key." >&2
  exit 1
fi
write_env_secret "ANTHROPIC_API_KEY" "$anthropic_key"

linear_key="${LINEAR_API_KEY:-}"
if [[ -z "$linear_key" ]]; then
  linear_key="$(fetch_secret "/linear/api-key" || true)"
fi
if [[ -z "$linear_key" ]]; then
  echo "LINEAR_API_KEY is required; set it as a GitHub secret or provide AWS access to /linear/api-key." >&2
  exit 1
fi
write_env_secret "LINEAR_API_KEY" "$linear_key"

echo "Configured Anthropic and Linear credentials for this runner."

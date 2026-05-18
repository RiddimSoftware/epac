#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
FAKE_AWS_LOG="${TMP_DIR}/aws.log"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/aws" <<'FAKE_AWS'
#!/usr/bin/env bash
set -euo pipefail

{
  echo "AWS_PROFILE=${AWS_PROFILE-__unset__}"
  echo "AWS_DEFAULT_PROFILE=${AWS_DEFAULT_PROFILE-__unset__}"
  echo "args=$*"
} >> "${FAKE_AWS_LOG}"

if [[ "${AWS_PROFILE+x}" == "x" || "${AWS_DEFAULT_PROFILE+x}" == "x" ]]; then
  echo "profile selector leaked to aws" >&2
  exit 99
fi

if [[ "$#" -ge 4 && "$1" == "s3" && "$2" == "cp" && "$3" == s3://* ]]; then
  exit 1
fi

exit 0
FAKE_AWS
chmod +x "${FAKE_BIN}/aws"

(
  cd "${TMP_DIR}"
  PATH="${FAKE_BIN}:${PATH}" \
  FAKE_AWS_LOG="${FAKE_AWS_LOG}" \
  AWS_ACCESS_KEY_ID="test-access-key" \
  AWS_SECRET_ACCESS_KEY="test-secret-key" \
  AWS_SESSION_TOKEN="test-session-token" \
  AWS_PROFILE="runner-profile" \
  AWS_DEFAULT_PROFILE="runner-default-profile" \
  BUILD_NUMBER="123" \
  GIT_SHA="0123456789abcdef0123456789abcdef01234567" \
  WORKFLOW_RUN_ID="456" \
  S3_BUCKET_PREFIX="s3://example-release-manifests" \
    "${REPO_ROOT}/scripts/ci/emit_release_manifest.sh" > "${TMP_DIR}/script.out"
)

jq -e \
  '.build_number == "123"
    and .git_sha == "0123456789abcdef0123456789abcdef01234567"
    and .workflow_run_id == "456"
    and .pr_numbers == []' \
  "${TMP_DIR}/release-manifest.json" >/dev/null

if grep -Eq 'AWS_(DEFAULT_)?PROFILE=(runner-|$)' "${FAKE_AWS_LOG}"; then
  echo "AWS profile selector leaked to fake aws:" >&2
  cat "${FAKE_AWS_LOG}" >&2
  exit 1
fi

grep -q 'Uploaded manifest to s3://example-release-manifests/0123456789abcdef0123456789abcdef01234567.json and s3://example-release-manifests/latest.json' "${TMP_DIR}/script.out"

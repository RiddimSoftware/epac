#!/usr/bin/env bash
# emit_release_manifest.sh — Generate and persist release-manifest.json for
# chain-of-custody linkage.
#
# Consumed by software-factory's chain-of-custody receipt generation.
# Do not remove without coordinating with FAC team.
#
# Inputs (environment):
#   BUILD_NUMBER      — TestFlight build number (string)
#   GIT_SHA           — Full 40-char commit SHA
#   WORKFLOW_RUN_ID   — GitHub Actions run ID
#   S3_BUCKET_PREFIX  — e.g. s3://riddimsoftware-factory-transcripts/release-manifests
#
# Outputs:
#   release-manifest.json in the working directory
#   Uploaded to ${S3_BUCKET_PREFIX}/${GIT_SHA}.json
#   Uploaded to ${S3_BUCKET_PREFIX}/latest.json

set -euo pipefail

BUILD_NUMBER="${BUILD_NUMBER:?}"
GIT_SHA="${GIT_SHA:?}"
WORKFLOW_RUN_ID="${WORKFLOW_RUN_ID:?}"
S3_BUCKET_PREFIX="${S3_BUCKET_PREFIX:?}"

UPLOADED_AT="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
MANIFEST_FILE="release-manifest.json"
PREV_MANIFEST_FILE="previous-manifest.json"

# Idempotency: if a manifest already exists for this SHA, reuse it.
if aws s3 cp "${S3_BUCKET_PREFIX}/${GIT_SHA}.json" "${MANIFEST_FILE}" 2>/dev/null; then
  echo "Manifest already exists for SHA ${GIT_SHA}. Re-uploading (idempotent)."
  aws s3 cp "${MANIFEST_FILE}" "${S3_BUCKET_PREFIX}/${GIT_SHA}.json"
  aws s3 cp "${MANIFEST_FILE}" "${S3_BUCKET_PREFIX}/latest.json"
  exit 0
fi

# Discover previous successful TestFlight build SHA from the latest manifest.
PREV_SHA=""
if aws s3 cp "${S3_BUCKET_PREFIX}/latest.json" "${PREV_MANIFEST_FILE}" 2>/dev/null; then
  PREV_SHA="$(jq -r '.git_sha // empty' "${PREV_MANIFEST_FILE}" 2>/dev/null || true)"
fi

# Derive PR numbers from merge-commit subjects between previous and current SHA.
PR_NUMBERS="[]"
if [[ -n "${PREV_SHA}" && "${PREV_SHA}" != "${GIT_SHA}" ]]; then
  PR_NUMBERS="$(git log --merges --pretty=%s "${PREV_SHA}..${GIT_SHA}" \
    | awk '/^Merge pull request #[0-9]+/ { if (match($0, /Merge pull request #([0-9]+)/, m)) print m[1] }' \
    | sort -u -n \
    | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(tonumber)')"
fi

jq -n \
  --arg build_number "${BUILD_NUMBER}" \
  --arg git_sha "${GIT_SHA}" \
  --argjson pr_numbers "${PR_NUMBERS}" \
  --arg workflow_run_id "${WORKFLOW_RUN_ID}" \
  --arg uploaded_at "${UPLOADED_AT}" \
  '{
    build_number: $build_number,
    git_sha: $git_sha,
    pr_numbers: $pr_numbers,
    workflow_run_id: $workflow_run_id,
    uploaded_at: $uploaded_at
  }' > "${MANIFEST_FILE}"

echo "Generated ${MANIFEST_FILE}:"
cat "${MANIFEST_FILE}"

aws s3 cp "${MANIFEST_FILE}" "${S3_BUCKET_PREFIX}/${GIT_SHA}.json"
aws s3 cp "${MANIFEST_FILE}" "${S3_BUCKET_PREFIX}/latest.json"

echo "Uploaded manifest to ${S3_BUCKET_PREFIX}/${GIT_SHA}.json and ${S3_BUCKET_PREFIX}/latest.json"

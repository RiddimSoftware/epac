#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_PACKAGE_PATH="${EVIDENCE_PACKAGE_PATH:-$ROOT_DIR/../evidence}"

cd "$ROOT_DIR"

if [[ -n "${EVIDENCE_BIN:-}" ]]; then
  exec "$EVIDENCE_BIN" "$@"
fi

if command -v evidence >/dev/null 2>&1; then
  exec evidence "$@"
fi

if [[ -d "$EVIDENCE_PACKAGE_PATH" ]]; then
  exec swift run --package-path "$EVIDENCE_PACKAGE_PATH" evidence -- "$@"
fi

echo "error: evidence CLI not found. Install evidence, set EVIDENCE_BIN, or set EVIDENCE_PACKAGE_PATH." >&2
exit 1

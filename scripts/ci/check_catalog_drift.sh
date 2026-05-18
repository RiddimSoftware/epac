#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
catalog="${1:-$repo_root/docs/architecture/use-case-catalog.md}"
status=0

cd "$repo_root"

while IFS= read -r path; do
  if [[ ! -e "$path" ]]; then
    printf 'Catalog drift: %s references missing path: %s\n' "${catalog#"$repo_root"/}" "$path" >&2
    printf 'Update the catalog entry or restore the file path in the same PR.\n' >&2
    status=1
  fi
done < <(
  awk '
    /^Current implementation:/ { in_current = 1; next }
    in_current && /^```/ { in_current = 0; next }
    in_current { print }
  ' "$catalog" |
  sed -E 's/^[[:space:]]+//; s/[[:space:]].*$//' |
  grep -E '^(\.github/|backend/|docs/|ios/|scripts/|shared/)' |
  sort -u
)

exit "$status"

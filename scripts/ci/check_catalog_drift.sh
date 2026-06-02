#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
catalog="${1:-$repo_root/docs/architecture/use-case-catalog.md}"
status=0

cd "$repo_root"

# 1. Implementation-path drift: every path listed in a `Current implementation:`
#    block must still exist on disk.
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

# 2. iOS Swift port drift: every row in the `## Ports` table whose `Stack`
#    column is `iOS Swift` and whose `Artifact status` column begins with
#    `Implemented:` must point to a file that declares `protocol <Name>`.
while IFS=$'\t' read -r port_name port_path; do
  [[ -z "$port_name" ]] && continue
  if [[ ! -f "$port_path" ]]; then
    printf 'Catalog drift: iOS Swift port `%s` claims `%s` as its implementation, but that file does not exist.\n' "$port_name" "$port_path" >&2
    printf 'Restore the file, fix the path in %s, or update the port row to `Planned / not yet implemented:`.\n' "${catalog#"$repo_root"/}" >&2
    status=1
    continue
  fi
  if ! grep -qE "^[[:space:]]*(public |internal |private |fileprivate )?protocol[[:space:]]+${port_name}\b" "$port_path"; then
    printf 'Catalog drift: iOS Swift port `%s` claims `%s` as its protocol declaration, but no `protocol %s` exists in that file.\n' \
      "$port_name" "$port_path" "$port_name" >&2
    printf 'Add `protocol %s` to %s, point the port row at the file that declares it, or update the row to `Planned / not yet implemented:`.\n' \
      "$port_name" "$port_path" >&2
    status=1
  fi
done < <(
  awk '
    /^## Ports[[:space:]]*$/ { in_ports = 1; next }
    in_ports && /^## / { in_ports = 0 }
    in_ports && /^\|/ {
      n = split($0, parts, /\|/)
      if (n < 6) next
      name_cell = parts[2]
      stack_cell = parts[3]
      artifact_cell = parts[5]
      gsub(/^[ \t]+|[ \t]+$/, "", name_cell)
      gsub(/^[ \t]+|[ \t]+$/, "", stack_cell)
      gsub(/^[ \t]+|[ \t]+$/, "", artifact_cell)
      if (!match(name_cell, /^`[A-Za-z_][A-Za-z0-9_]*`$/)) next
      port_name = substr(name_cell, 2, length(name_cell) - 2)
      if (stack_cell != "iOS Swift") next
      if (index(artifact_cell, "Implemented:") != 1) next
      rest = substr(artifact_cell, length("Implemented:") + 1)
      if (!match(rest, /`[^`]+`/)) next
      port_path = substr(rest, RSTART + 1, RLENGTH - 2)
      printf "%s\t%s\n", port_name, port_path
    }
  ' "$catalog"
)

exit "$status"

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
backend_dir="$repo_root/backend"
remediation="Use case packages must not import frameworks. Move framework usage to internal/adapter/. See docs/architecture/use-case-catalog.md."
status=0

is_standard_library_import() {
  local import_path="$1"
  local first_component="${import_path%%/*}"
  [[ "$first_component" != *.* ]]
}

is_own_internal_import() {
  local import_path="$1"
  local module_path="$2"
  [[ -n "$module_path" ]] && { [[ "$import_path" == "$module_path/internal" ]] || [[ "$import_path" == "$module_path/internal/"* ]]; }
}

extract_imports() {
  awk '
    /^import[[:space:]]+"/ {
      line = $0
      sub(/^import[[:space:]]+"/, "", line)
      sub(/".*$/, "", line)
      print line
      next
    }
    /^import[[:space:]]*\(/ {
      in_import = 1
      next
    }
    in_import && /^\)/ {
      in_import = 0
      next
    }
    in_import {
      line = $0
      sub(/\/\/.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") {
        next
      }
      split(line, parts, "\"")
      if (length(parts) >= 2) {
        print parts[2]
      }
    }
  ' "$1"
}

while IFS= read -r file; do
  relative="${file#"$backend_dir"/}"
  service="${relative%%/*}"
  module_path="$(awk '/^module[[:space:]]+/ { print $2; exit }' "$backend_dir/$service/go.mod" 2>/dev/null || true)"

  while IFS= read -r import_path; do
    case "$import_path" in
      github.com/jackc/pgx/v5|github.com/jackc/pgx/v5/*|github.com/aws/aws-lambda-go|github.com/aws/aws-lambda-go/*|github.com/aws/aws-sdk-go-v2|github.com/aws/aws-sdk-go-v2/*|net/http)
        printf '%s imports forbidden framework package %s. %s\n' "${file#"$repo_root"/}" "$import_path" "$remediation" >&2
        status=1
        continue
        ;;
    esac

    if is_standard_library_import "$import_path"; then
      continue
    fi
    if is_own_internal_import "$import_path" "$module_path"; then
      continue
    fi

    printf '%s imports non-standard package %s. %s\n' "${file#"$repo_root"/}" "$import_path" "$remediation" >&2
    status=1
  done < <(extract_imports "$file")
done < <(find "$backend_dir" -path '*/internal/usecase/*.go' -type f | sort)

exit "$status"

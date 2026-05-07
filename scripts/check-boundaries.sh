#!/usr/bin/env bash
# Checks that inward files (application policy, domain models) do not import
# framework types from the outer rings (SwiftUI, SwiftData, UIKit, Lambda events,
# APNs, pgx, URLSession).
#
# Exit codes:
#   0 – all checks passed (or skipped with notice)
#   1 – one or more violations found
#
# Run from the repo root:
#   scripts/check-boundaries.sh
#
# See docs/architecture/use-case-catalog.md § Boundary Check for context.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VIOLATIONS=0

# ── helpers ────────────────────────────────────────────────────────────────────

pass()  { echo "  ✓ $*"; }
fail()  { echo "  ✗ VIOLATION: $*"; VIOLATIONS=$((VIOLATIONS + 1)); }
skip()  { echo "  ↷ SKIP: $*"; }
header(){ echo; echo "── $* ──"; }

grep_files() {
  # grep_files <pattern> <path_glob>
  # Prints matching file:line pairs; returns 1 if no matches (grep behaviour).
  local pattern="$1"; shift
  grep -rn --include="$1" "$pattern" "$REPO_ROOT" 2>/dev/null || true
}

# ── iOS Domain boundary (EPAC-1741) ───────────────────────────────────────────
header "iOS Domain layer (ios/epac/Domain/)"

DOMAIN_DIR="$REPO_ROOT/ios/epac/Domain"
if [[ -d "$DOMAIN_DIR" ]]; then
  FRAMEWORK_IMPORTS=$(grep_files \
    'import SwiftUI\|import SwiftData\|import UIKit\|import StoreKit' \
    "*.swift" "$DOMAIN_DIR")
  if [[ -n "$FRAMEWORK_IMPORTS" ]]; then
    while IFS= read -r line; do fail "$line"; done <<< "$FRAMEWORK_IMPORTS"
  else
    pass "No SwiftUI/SwiftData/UIKit imports in ios/epac/Domain/"
  fi
else
  skip "ios/epac/Domain/ does not exist yet — boundary will be enforced by EPAC-1741"
fi

# ── iOS Application layer (EPAC-1742) ─────────────────────────────────────────
header "iOS Application layer (ios/epac/Application/)"

APP_DIR="$REPO_ROOT/ios/epac/Application"
if [[ -d "$APP_DIR" ]]; then
  FRAMEWORK_IMPORTS=$(grep_files \
    'import SwiftUI\|import SwiftData\|import UIKit\|import StoreKit' \
    "*.swift" "$APP_DIR")
  if [[ -n "$FRAMEWORK_IMPORTS" ]]; then
    while IFS= read -r line; do fail "$line"; done <<< "$FRAMEWORK_IMPORTS"
  else
    pass "No SwiftUI/SwiftData/UIKit imports in ios/epac/Application/"
  fi
else
  skip "ios/epac/Application/ does not exist yet — boundary will be enforced by EPAC-1742"
fi

# ── Backend application packages ──────────────────────────────────────────────
header "Backend application packages (backend/*/application/*.go)"

# device-register/application is the only backend application package today.
# Additional packages are added by EPAC-1743.

BACKEND_APP_DIRS=()
while IFS= read -r d; do
  BACKEND_APP_DIRS+=("$d")
done < <(find "$REPO_ROOT/backend" -type d -name "application" 2>/dev/null || true)

if [[ ${#BACKEND_APP_DIRS[@]} -eq 0 ]]; then
  skip "No backend/*/application/ directories found — boundaries added by EPAC-1743"
else
  for dir in "${BACKEND_APP_DIRS[@]}"; do
    relative="${dir#"$REPO_ROOT/"}"

    # Check: must not import Lambda event packages
    LAMBDA_IMPORTS=$(grep -rn \
      'github.com/aws/aws-lambda-go/events\|github.com/aws/aws-lambda-go/lambda' \
      "$dir" 2>/dev/null || true)
    if [[ -n "$LAMBDA_IMPORTS" ]]; then
      while IFS= read -r line; do fail "Lambda event import in $relative: $line"; done <<< "$LAMBDA_IMPORTS"
    else
      pass "No Lambda event imports in $relative"
    fi

    # Check: must not import pgx directly
    PGX_IMPORTS=$(grep -rn \
      '"github.com/jackc/pgx' \
      "$dir" 2>/dev/null || true)
    if [[ -n "$PGX_IMPORTS" ]]; then
      while IFS= read -r line; do fail "pgx import in $relative: $line"; done <<< "$PGX_IMPORTS"
    else
      pass "No pgx imports in $relative"
    fi

    # Check: must not import net/http directly (should use a port)
    HTTP_IMPORTS=$(grep -rn \
      '"net/http"' \
      "$dir" 2>/dev/null || true)
    if [[ -n "$HTTP_IMPORTS" ]]; then
      while IFS= read -r line; do fail "net/http import in $relative: $line"; done <<< "$HTTP_IMPORTS"
    else
      pass "No net/http imports in $relative"
    fi
  done
fi

# ── EPAC-1743 reminder ─────────────────────────────────────────────────────────
header "Backend use-case coverage (EPAC-1743)"

EXPECTED_BACKENDS=(
  "backend/live-status"
  "backend/search"
  "backend/member-speeches"
  "backend/topic-notifier"
  "backend/daily-fetch"
)

for svc in "${EXPECTED_BACKENDS[@]}"; do
  if [[ -d "$REPO_ROOT/$svc/application" ]]; then
    pass "$svc/application/ exists"
  else
    skip "$svc/application/ not yet created — will be added by EPAC-1743"
  fi
done

# ── Summary ────────────────────────────────────────────────────────────────────
echo
if [[ $VIOLATIONS -eq 0 ]]; then
  echo "All boundary checks passed (violations: 0)."
  exit 0
else
  echo "Boundary violations found: $VIOLATIONS"
  echo "See docs/architecture/use-case-catalog.md § Boundary Check for guidance."
  exit 1
fi

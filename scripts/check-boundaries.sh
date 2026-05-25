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
  # grep_files <pattern> <path_glob> <directory>
  # Prints matching file:line pairs; returns 1 if no matches (grep behaviour).
  local pattern="$1"
  local glob="$2"
  local dir="${3:-$REPO_ROOT}"
  grep -rn --include="$glob" "$pattern" "$dir" 2>/dev/null || true
}

IOS_FORBIDDEN_PATTERN='import SwiftUI\|import SwiftData\|import UIKit\|import StoreKit\|import UserNotifications\|URLSession\|UNUserNotificationCenter\|UNNotification\|UNNotificationRequest\|UNNotificationResponse\|UNMutableNotificationContent\|UIApplication\|registerForRemoteNotifications'
IOS_APPLICATION_FORBIDDEN_PATTERN="$IOS_FORBIDDEN_PATTERN"
HANSARD_ADAPTER_FORBIDDEN_PATTERN='import SwiftUI\|import SwiftData\|import UIKit'

# ── iOS Domain boundary (EPAC-1741) ───────────────────────────────────────────
header "iOS Domain layer (ios/epac/Domain/)"

DOMAIN_DIR="$REPO_ROOT/ios/epac/Domain"
if [[ -d "$DOMAIN_DIR" ]]; then
  FRAMEWORK_IMPORTS=$(grep_files \
    "$IOS_FORBIDDEN_PATTERN" \
    "*.swift" "$DOMAIN_DIR")
  if [[ -n "$FRAMEWORK_IMPORTS" ]]; then
    while IFS= read -r line; do fail "$line"; done <<< "$FRAMEWORK_IMPORTS"
  else
    pass "No SwiftUI/SwiftData/UIKit/APNs/URLSession imports in ios/epac/Domain/"
  fi
else
  skip "ios/epac/Domain/ does not exist yet — boundary will be enforced by EPAC-1741"
fi

# ── iOS Application layer (EPAC-1742) ─────────────────────────────────────────
header "iOS Application layer (ios/epac/Application/)"

APP_DIR="$REPO_ROOT/ios/epac/Application"
if [[ -d "$APP_DIR" ]]; then
  FRAMEWORK_IMPORTS=$(grep_files \
    "$IOS_APPLICATION_FORBIDDEN_PATTERN" \
    "*.swift" "$APP_DIR")
  if [[ -n "$FRAMEWORK_IMPORTS" ]]; then
    while IFS= read -r line; do fail "$line"; done <<< "$FRAMEWORK_IMPORTS"
  else
    pass "No SwiftUI/SwiftData/UIKit/APNs/URLSession imports in ios/epac/Application/"
  fi
else
  skip "ios/epac/Application/ does not exist yet — boundary will be enforced by EPAC-1742"
fi

# ── iOS Hansard adapter boundary (EPAC-2029) ─────────────────────────────────
header "iOS Hansard adapters (ios/epac/Data/Adapters/Hansard/**/*Adapter.swift)"

HANSARD_ADAPTER_DIR="$REPO_ROOT/ios/epac/Data/Adapters/Hansard"
if [[ -d "$HANSARD_ADAPTER_DIR" ]]; then
  ADAPTER_FILES=$(find "$HANSARD_ADAPTER_DIR" -type f -name "*Adapter.swift" 2>/dev/null || true)
  if [[ -n "$ADAPTER_FILES" ]]; then
    ADAPTER_VIOLATIONS=$(
      while IFS= read -r file; do
        grep -n "$HANSARD_ADAPTER_FORBIDDEN_PATTERN" "$file" 2>/dev/null | sed "s#^#$file:#" || true
      done <<< "$ADAPTER_FILES"
    )
    if [[ -n "$ADAPTER_VIOLATIONS" ]]; then
      while IFS= read -r line; do
        fail "$line — This adapter imports a UI/persistence framework. Move that concern to a Repository or ViewModel layer. See docs/architecture/use-case-catalog.md."
      done <<< "$ADAPTER_VIOLATIONS"
    else
      pass "No SwiftUI/SwiftData/UIKit imports in Hansard adapter files"
    fi
  else
    skip "No *Adapter.swift files in ios/epac/Data/Adapters/Hansard/ yet"
  fi
else
  skip "ios/epac/Data/Adapters/Hansard/ does not exist yet"
fi

# ── Backend application packages ──────────────────────────────────────────────
header "Backend application packages (backend/*/application/*.go)"

# Backend application packages are added incrementally by EPAC-1743.

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

    # Check: must not import APNs clients directly.
    APNS_IMPORTS=$(
      {
        grep -rn '"github.com/sideshow/apns2' "$dir"
      } 2>/dev/null || true
    )
    if [[ -n "$APNS_IMPORTS" ]]; then
      while IFS= read -r line; do fail "APNs client import in $relative: $line"; done <<< "$APNS_IMPORTS"
    else
      pass "No APNs client imports in $relative"
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
  "backend/member-speeches"
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

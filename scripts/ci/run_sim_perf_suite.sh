#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

RUNNER_TEMP_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
RESULT_BUNDLE="${PERF_RESULT_BUNDLE:-$RUNNER_TEMP_DIR/Performance.xcresult}"
LOG_FILE="${PERF_LOG_FILE:-$RUNNER_TEMP_DIR/performance-suite-xcodebuild.log}"
DERIVED_DATA_PATH="${PERF_DERIVED_DATA_PATH:-$RUNNER_TEMP_DIR/performance-derived-data}"
PACKAGE_CACHE="$RUNNER_TEMP_DIR/xcode-package-cache"
CLONED_PACKAGES="$RUNNER_TEMP_DIR/xcode-cloned-source-packages"
SUMMARY_DIR="$RUNNER_TEMP_DIR/performance-summary"
SUMMARY_FILE="$SUMMARY_DIR/performance-suite.md"
FLAT_SUMMARY="$SUMMARY_DIR/flat-metrics.md"
SIGNPOST_SUMMARY="$SUMMARY_DIR/signpost-metrics.md"
IN_PROCESS_SUMMARY="$SUMMARY_DIR/in-process-metrics.md"
BUNDLE_ID="net.dinglebox.cabinetdoor"
UITEST_RUNNER_BUNDLE_ID="com.riddimsoftware.epacUITests.xctrunner"

mkdir -p "$SUMMARY_DIR"

configure_git_for_package_resolution() {
  local git_config="$RUNNER_TEMP_DIR/ci-gitconfig"
  cat > "$git_config" <<'EOF'
[url "https://github.com/"]
  insteadOf = git@github.com:
  insteadOf = ssh://git@github.com/
  insteadOf = git://github.com/
EOF
  export GIT_CONFIG_GLOBAL="$git_config"
}

resolve_simulator() {
  if [ -n "${SIMULATOR_UDID:-}" ]; then
    SIMULATOR_NAME="${SIMULATOR_NAME:-$SIMULATOR_UDID}"
    SIMULATOR_RUNTIME="${SIMULATOR_RUNTIME:-provided destination}"
    return
  fi

  local simulator_env="$RUNNER_TEMP_DIR/performance-simulator.env"
  SIMULATOR_ENV="$simulator_env" python3 <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys


def version_tuple(value):
    return tuple(int(part) for part in re.findall(r"\d+", value))


runtimes = json.loads(
    subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "--json"], text=True)
).get("runtimes", [])
ios_26_runtimes = [
    runtime
    for runtime in runtimes
    if runtime.get("isAvailable", True)
    and (
        runtime.get("platform") == "iOS"
        or "iOS" in runtime.get("name", "")
        or "com.apple.CoreSimulator.SimRuntime.iOS" in runtime.get("identifier", "")
    )
    and str(runtime.get("version", "")).startswith("26.")
]
if not ios_26_runtimes:
    sys.exit("No available iOS 26.x Simulator runtime found.")

runtime = max(ios_26_runtimes, key=lambda item: version_tuple(str(item.get("version", ""))))
devices_by_runtime = json.loads(
    subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"], text=True)
).get("devices", {})
devices = [
    device
    for device in devices_by_runtime.get(runtime["identifier"], [])
    if device.get("isAvailable", True)
]

preferred = [device for device in devices if device.get("name") == "iPhone 17 Pro Max"]
fallback = [
    device
    for device in devices
    if device.get("name", "").startswith("iPhone ")
    and (" Pro" in device.get("name", "") or "Pro Max" in device.get("name", ""))
]


def device_score(device):
    name = device.get("name", "")
    generation = max([int(part) for part in re.findall(r"\d+", name)] or [0])
    tier = 2 if "Pro Max" in name else 1 if " Pro" in name else 0
    return (tier, generation, name)


if preferred:
    device = preferred[0]
elif fallback:
    device = max(fallback, key=device_score)
else:
    sys.exit("No available iPhone Pro or Pro Max simulator found on the iOS 26.x runtime.")

values = {
    "SIMULATOR_UDID": device["udid"],
    "SIMULATOR_NAME": device["name"],
    "SIMULATOR_RUNTIME": f'{runtime.get("name", "iOS")} {runtime.get("version", "")}'.strip(),
}
with open(os.environ["SIMULATOR_ENV"], "w", encoding="utf-8") as handle:
    for key, value in values.items():
        handle.write(f"{key}={shlex.quote(value)}\n")
PY
  # shellcheck source=/dev/null
  source "$simulator_env"
}

append_summary() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "$SUMMARY_FILE" >> "$GITHUB_STEP_SUMMARY"
  fi
}

configure_git_for_package_resolution
resolve_simulator

echo "Resolved $SIMULATOR_NAME on $SIMULATOR_RUNTIME ($SIMULATOR_UDID)"

xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl terminate "$SIMULATOR_UDID" "$UITEST_RUNNER_BUNDLE_ID" >/dev/null 2>&1 || true

rm -rf "$RESULT_BUNDLE" "$DERIVED_DATA_PATH" "$PACKAGE_CACHE" "$CLONED_PACKAGES"
mkdir -p "$PACKAGE_CACHE" "$CLONED_PACKAGES"

set +e
xcodebuild test \
  -project ios/epac.xcodeproj \
  -scheme epac \
  -configuration Release \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$CLONED_PACKAGES" \
  -packageCachePath "$PACKAGE_CACHE" \
  -disablePackageRepositoryCache \
  -resultBundlePath "$RESULT_BUNDLE" \
  -testPlan Performance \
  -parallel-testing-enabled NO \
  -skip-testing:epacUITests/ScrollHitchPerfTests \
  -skip-testing:epacUITests/FreshInstallPerfTests \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_TESTABILITY=YES \
  2>&1 | tee "$LOG_FILE"
xcode_status="${PIPESTATUS[0]}"
set -e

{
  echo "## Simulator performance suite"
  echo ""
  echo "| Environment | Value |"
  echo "| --- | --- |"
  echo "| Simulator | $SIMULATOR_NAME |"
  echo "| Runtime | $SIMULATOR_RUNTIME |"
  echo "| Result bundle | $(basename "$RESULT_BUNDLE") |"
  echo "| PR-safe exclusions | epacUITests/FreshInstallPerfTests, epacUITests/ScrollHitchPerfTests |"
} > "$SUMMARY_FILE"

flat_status=1
signpost_status=1
in_process_status=1

if [ -d "$RESULT_BUNDLE" ]; then
  set +e
  python3 scripts/ci/perf_parse.py \
    "$RESULT_BUNDLE" \
    --budget-dir .github/perf-budgets \
    --platform sim \
    --summary-markdown "$FLAT_SUMMARY"
  flat_status="$?"

  python3 scripts/ci/verify_signpost_perf_metrics.py \
    --summary-markdown "$SIGNPOST_SUMMARY" \
    "$RESULT_BUNDLE" \
    .github/perf-budgets/signpost-phase-durations.json
  signpost_status="$?"

  python3 scripts/perf/check_in_process_metrics.py \
    --xcresult "$RESULT_BUNDLE" \
    --manifest .github/perf-budgets/in-process-sim/manifest.json \
    --summary-markdown "$IN_PROCESS_SUMMARY"
  in_process_status="$?"
  set -e

  for partial_summary in "$FLAT_SUMMARY" "$SIGNPOST_SUMMARY" "$IN_PROCESS_SUMMARY"; do
    if [ -f "$partial_summary" ]; then
      echo "" >> "$SUMMARY_FILE"
      cat "$partial_summary" >> "$SUMMARY_FILE"
    fi
  done
else
  {
    echo ""
    echo "### Performance metrics"
    echo ""
    echo "No result bundle was produced, so metric parsing could not run."
  } >> "$SUMMARY_FILE"
fi

if [ "$xcode_status" -eq 0 ] \
  && [ "$flat_status" -eq 0 ] \
  && [ "$signpost_status" -eq 0 ] \
  && [ "$in_process_status" -eq 0 ]; then
  result="passed"
else
  result="failed"
fi

{
  echo ""
  echo "### Result"
  echo ""
  echo "| Check | Status |"
  echo "| --- | ---: |"
  echo "| xcodebuild | $xcode_status |"
  echo "| flat metric budgets | $flat_status |"
  echo "| signpost metric budgets | $signpost_status |"
  echo "| in-process metric budgets | $in_process_status |"
  echo ""
  echo "**Result:** $result"
} >> "$SUMMARY_FILE"

append_summary

if [ "$xcode_status" -ne 0 ]; then
  exit "$xcode_status"
fi
if [ "$flat_status" -ne 0 ]; then
  exit "$flat_status"
fi
if [ "$signpost_status" -ne 0 ]; then
  exit "$signpost_status"
fi
if [ "$in_process_status" -ne 0 ]; then
  exit "$in_process_status"
fi

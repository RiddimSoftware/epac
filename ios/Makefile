SHELL := /bin/bash
.PHONY: build deploy-simulator simulator test perf-sim ipad-build ipad-deploy-simulator ipad-simulator side-by-side catalyst-build catalyst-run

OUTPUT_DIR = .build
# Dynamically detect an available iPhone simulator
AVAILABLE_SIM := $(shell xcrun simctl list devices available | grep -v unavailable | grep "iPhone" | head -1)
DETECTED_SIM_NAME := $(shell echo '$(AVAILABLE_SIM)' | sed -E 's/^[[:space:]]+(.*) \([A-F0-9-]{36}\).*/\1/')
DETECTED_SIM_UUID := $(shell echo '$(AVAILABLE_SIM)' | grep -oE '[A-F0-9-]{36}')
AVAILABLE_IPAD_SIM := $(shell match=$$(xcrun simctl list devices available 2>/dev/null | grep -v unavailable | grep "iPad Pro (13-inch)" | head -1); if [ -z "$$match" ]; then match=$$(xcrun simctl list devices available 2>/dev/null | grep -v unavailable | grep "iPad Pro (12.9-inch)" | head -1); fi; if [ -z "$$match" ]; then match=$$(xcrun simctl list devices available 2>/dev/null | grep -v unavailable | grep "iPad" | head -1); fi; echo "$$match")
DETECTED_IPAD_SIM_NAME := $(shell echo '$(AVAILABLE_IPAD_SIM)' | sed -E 's/^[[:space:]]+(.*) \([A-F0-9-]{36}\).*/\1/')
DETECTED_IPAD_SIM_UUID := $(shell echo '$(AVAILABLE_IPAD_SIM)' | grep -oE '[A-F0-9-]{36}')

SIM_NAME ?= $(DETECTED_SIM_NAME)
SIM_UUID = $(shell xcrun simctl list devices available | grep -v unavailable | grep "$(SIM_NAME)" | head -1 | grep -oE '[A-F0-9-]{36}' || echo "$(DETECTED_SIM_UUID)")
IPAD_SIM_NAME ?= $(DETECTED_IPAD_SIM_NAME)
IPAD_SIM_UUID = $(shell if [ -n "$(IPAD_SIM_NAME)" ]; then xcrun simctl list devices available 2>/dev/null | grep -v unavailable | grep "$(IPAD_SIM_NAME)" | head -1 | grep -oE '[A-F0-9-]{36}' || echo "$(DETECTED_IPAD_SIM_UUID)"; else echo "$(DETECTED_IPAD_SIM_UUID)"; fi)
APP_PATH = $(OUTPUT_DIR)/Build/Products/Debug-iphonesimulator/epac.app
SIGNPOST_PERF_RESULT_BUNDLE = $(OUTPUT_DIR)/SignpostPerf.xcresult
SIGNPOST_PERF_BUDGET_FILE = ../.github/perf-budgets/signpost-phase-durations.json
SDK ?= iphonesimulator
BUNDLE_ID = net.dinglebox.cabinetdoor
DESTINATION = 'platform=iOS Simulator,id=$(SIM_UUID)'
IPAD_DESTINATION = 'platform=iOS Simulator,id=$(IPAD_SIM_UUID)'
IPHONE_SIM_ERROR = No iPhone simulator available. Install one via Xcode → Settings → Platforms.
IPAD_SIM_ERROR = No iPad Pro simulator available. Install one via Xcode → Settings → Platforms.
CATALYST_ARCH = $(if $(filter arm64,$(shell uname -m)),arm64,x86_64)
CATALYST_DESTINATION = 'platform=macOS,variant=Mac Catalyst,arch=$(CATALYST_ARCH)'
CATALYST_APP_PATH = $(OUTPUT_DIR)/Build/Products/Debug-maccatalyst/epac.app

build:
	set -o pipefail && xcodebuild -project epac.xcodeproj -scheme epac -configuration Debug -sdk $(SDK) -destination $(DESTINATION) -derivedDataPath $(OUTPUT_DIR) build -quiet | xcbeautify --quiet

test:
	rm -rf $(OUTPUT_DIR)/TestResults.xcresult
	set -o pipefail && xcodebuild test -project epac.xcodeproj -scheme epac -destination $(DESTINATION) -derivedDataPath $(OUTPUT_DIR) -enableCodeCoverage YES -resultBundlePath $(OUTPUT_DIR)/TestResults.xcresult $(if $(TEST_ONLY),-only-testing:epacTests/$(TEST_ONLY)) | xcbeautify
	@echo "\n--- Code Coverage Summary (App Source Files) ---"
	@xcrun xccov view --report --json $(OUTPUT_DIR)/TestResults.xcresult > $(OUTPUT_DIR)/coverage.json
	@jq -r '.targets[] | select(.name == "epac.app" or .name == "epac-clip.app") | .files[] | select(.path | endswith(".swift")) | "\(.path | split("/") | last): \((.lineCoverage * 10000 | round / 100))%"' $(OUTPUT_DIR)/coverage.json | sort -u | column -t -s ":"

perf-sim:
	@test -n "$(SIM_UUID)" || { echo "$(IPHONE_SIM_ERROR)" >&2; exit 1; }
	xcrun simctl boot $(SIM_UUID) >/dev/null 2>&1 || true
	xcrun simctl bootstatus $(SIM_UUID) -b
	xcrun simctl terminate $(SIM_UUID) $(BUNDLE_ID) >/dev/null 2>&1 || true
	xcrun simctl terminate $(SIM_UUID) com.riddimsoftware.epacUITests.xctrunner >/dev/null 2>&1 || true
	rm -rf $(SIGNPOST_PERF_RESULT_BUNDLE)
	set -o pipefail && xcodebuild test -project epac.xcodeproj -scheme epac -destination $(DESTINATION) -derivedDataPath $(OUTPUT_DIR) -resultBundlePath $(SIGNPOST_PERF_RESULT_BUNDLE) -only-testing:epacUITests/SignpostPerfTests | xcbeautify
	python3 ../scripts/ci/verify_signpost_perf_metrics.py $(SIGNPOST_PERF_RESULT_BUNDLE) $(SIGNPOST_PERF_BUDGET_FILE)

deploy-simulator:
	xcrun simctl install $(SIM_UUID) $(APP_PATH)
	xcrun simctl launch $(SIM_UUID) $(BUNDLE_ID)

simulator:
	$(MAKE) build SDK=iphonesimulator
	$(MAKE) deploy-simulator

ipad-build: ## Build epac for the preferred iPad simulator destination.
	@test -n "$(IPAD_SIM_UUID)" || { echo "$(IPAD_SIM_ERROR)" >&2; exit 1; }
	set -o pipefail && xcodebuild -project epac.xcodeproj -scheme epac -configuration Debug -sdk iphonesimulator -destination $(IPAD_DESTINATION) -derivedDataPath $(OUTPUT_DIR) build -quiet | xcbeautify --quiet

ipad-deploy-simulator: ## Install and launch epac on the preferred iPad simulator.
	@test -n "$(IPAD_SIM_UUID)" || { echo "$(IPAD_SIM_ERROR)" >&2; exit 1; }
	xcrun simctl boot $(IPAD_SIM_UUID) >/dev/null 2>&1 || true
	xcrun simctl bootstatus $(IPAD_SIM_UUID) -b
	xcrun simctl install $(IPAD_SIM_UUID) $(APP_PATH)
	xcrun simctl launch $(IPAD_SIM_UUID) $(BUNDLE_ID)

ipad-simulator: ## Build, install, and launch epac on the preferred iPad simulator.
	$(MAKE) ipad-build
	$(MAKE) ipad-deploy-simulator

side-by-side: ## Boot, install, and launch epac on iPhone and iPad simulators together.
	@test -n "$(SIM_UUID)" || { echo "$(IPHONE_SIM_ERROR)" >&2; exit 1; }
	@test -n "$(IPAD_SIM_UUID)" || { echo "$(IPAD_SIM_ERROR)" >&2; exit 1; }
	(xcrun simctl boot $(SIM_UUID) >/dev/null 2>&1 || true) & (xcrun simctl boot $(IPAD_SIM_UUID) >/dev/null 2>&1 || true) & wait
	xcrun simctl bootstatus $(SIM_UUID) -b
	xcrun simctl bootstatus $(IPAD_SIM_UUID) -b
	$(MAKE) ipad-build
	xcrun simctl install $(SIM_UUID) $(APP_PATH)
	xcrun simctl install $(IPAD_SIM_UUID) $(APP_PATH)
	xcrun simctl launch $(SIM_UUID) $(BUNDLE_ID)
	xcrun simctl launch $(IPAD_SIM_UUID) $(BUNDLE_ID)

catalyst-build: ## Build epac for Mac Catalyst on the local Mac.
	set -o pipefail && xcodebuild -project epac.xcodeproj -scheme epac -configuration Debug -sdk macosx -destination $(CATALYST_DESTINATION) -derivedDataPath $(OUTPUT_DIR) build -quiet | xcbeautify --quiet

catalyst-run: ## Build and open the Mac Catalyst app locally.
	$(MAKE) catalyst-build
	open "$(CATALYST_APP_PATH)"

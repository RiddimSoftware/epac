SHELL := /bin/bash
.PHONY: build deploy-simulator simulator test

OUTPUT_DIR = .build
# Dynamically detect an available iPhone simulator
AVAILABLE_SIM := $(shell xcrun simctl list devices available | grep -v unavailable | grep "iPhone" | head -1)
DETECTED_SIM_NAME := $(shell echo '$(AVAILABLE_SIM)' | sed -E 's/^[[:space:]]+(.*) \([A-F0-9-]{36}\).*/\1/')
DETECTED_SIM_UUID := $(shell echo '$(AVAILABLE_SIM)' | grep -oE '[A-F0-9-]{36}')

SIM_NAME ?= $(DETECTED_SIM_NAME)
SIM_UUID = $(shell xcrun simctl list devices available | grep -v unavailable | grep "$(SIM_NAME)" | head -1 | grep -oE '[A-F0-9-]{36}' || echo "$(DETECTED_SIM_UUID)")
APP_PATH = $(OUTPUT_DIR)/Build/Products/Debug-iphonesimulator/epac.app
SDK ?= iphonesimulator
BUNDLE_ID = net.dinglebox.cabinetdoor
DESTINATION = 'platform=iOS Simulator,id=$(SIM_UUID)'

build:
	set -o pipefail && xcodebuild -project epac.xcodeproj -scheme epac -configuration Debug -sdk $(SDK) -destination $(DESTINATION) -derivedDataPath $(OUTPUT_DIR) build -quiet | xcbeautify --quiet

test:
	rm -rf $(OUTPUT_DIR)/TestResults.xcresult
	set -o pipefail && xcodebuild test -project epac.xcodeproj -scheme epac -destination $(DESTINATION) -derivedDataPath $(OUTPUT_DIR) -enableCodeCoverage YES -resultBundlePath $(OUTPUT_DIR)/TestResults.xcresult $(if $(TEST_ONLY),-only-testing:epacTests/$(TEST_ONLY)) | xcbeautify
	@echo "\n--- Code Coverage Summary (App Source Files) ---"
	@xcrun xccov view --report --json $(OUTPUT_DIR)/TestResults.xcresult > $(OUTPUT_DIR)/coverage.json
	@jq -r '.targets[] | select(.name == "epac.app" or .name == "epac-clip.app") | .files[] | select(.path | endswith(".swift")) | "\(.path | split("/") | last): \((.lineCoverage * 10000 | round / 100))%"' $(OUTPUT_DIR)/coverage.json | sort -u | column -t -s ":"

deploy-simulator:
	xcrun simctl install $(SIM_UUID) $(APP_PATH)
	xcrun simctl launch $(SIM_UUID) $(BUNDLE_ID)

simulator:
	$(MAKE) build SDK=iphonesimulator
	$(MAKE) deploy-simulator

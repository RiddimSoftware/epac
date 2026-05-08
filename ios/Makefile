SHELL := /bin/bash
.PHONY: build deploy-simulator simulator test

OUTPUT_DIR = .build
SIM_NAME ?= iPhone 17 Pro Max
SIM_UUID = $(shell xcrun simctl list devices available | grep "$(SIM_NAME)" | grep -v unavailable | head -1 | grep -oE '[A-F0-9-]{36}')
APP_PATH = $(OUTPUT_DIR)/Build/Products/Debug-iphonesimulator/epac.app
SDK ?= iphonesimulator
BUNDLE_ID = net.dinglebox.cabinetdoor
DESTINATION = 'platform=iOS Simulator,name=$(SIM_NAME)'

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

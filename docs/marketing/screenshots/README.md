# App Store Screenshots

EPAC-109 screenshot exports live here.

Generate source captures with the App Store screenshot UI test:

```sh
APPSTORE_SCREENSHOT_DIR=/tmp/epac-appstore-screenshots \
xcodebuild test \
  -project epac.xcodeproj \
  -scheme epac \
  -destination 'platform=iOS Simulator,name=EPAC App Store 16 Pro Max' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/epac-afnetyeysumivgfzkpjhhfcnazhs \
  -only-testing:epacUITests/epacUITests/testCaptureAppStoreScreenshotSources
```

Render App Store-ready assets:

```sh
scripts/marketing/render_app_store_screenshots.sh /tmp/epac-appstore-screenshots docs/marketing/screenshots
```

The capture route uses `Evidence.ScreenshotPlan`, the app's `-AppStoreScreenshots` launch argument, and official-record sample data from the House of Commons Hansard fixture already committed in the test suite. Resizing is delegated to `evidence resize` through `scripts/marketing/render_app_store_screenshots.sh`.

The render script writes:

- 6 iPhone 6.9-inch screenshots using the base scene filenames.
- 6 iPad Pro 13-inch screenshots prefixed with `APP_IPAD_PRO_3GEN_129_`.
- 6 iPad Pro 12.9-inch screenshots prefixed with `APP_IPAD_PRO_129_`.

To refresh the App Store upload directory from the committed marketing set:

```sh
scripts/marketing/render_app_store_screenshots.sh docs/marketing/screenshots ios/fastlane/screenshots/en-CA
```

See `docs/marketing/evidence-workflows.md` for the full local workflow.

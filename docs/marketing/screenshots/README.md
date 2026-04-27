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

Render App Store-ready 6.9-inch assets:

```sh
scripts/marketing/render_app_store_screenshots.sh /tmp/epac-appstore-screenshots docs/marketing/screenshots
```

The capture route uses the app's `-AppStoreScreenshots` launch argument and official-record sample data from the House of Commons Hansard fixture already committed in the test suite.

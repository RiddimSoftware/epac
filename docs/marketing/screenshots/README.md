# App Store Screenshots

## Capture pipeline

Screenshots are captured natively on each target device using Fastlane Snapshot.
The Snapfile at `ios/fastlane/Snapfile` lists 4 devices:

- iPhone 16 Pro Max (6.9-inch, 1320×2868)
- iPhone 16 (6.1-inch, 1290×2796)
- iPad Pro 13-inch M4 (2064×2752)
- iPad Pro 11-inch M4 (1668×2388)

Each device captures 6 scenes via `AppStoreScreenshotTests.testCaptureAppStoreScreenshotSources`,
producing 24 PNGs total in `ios/fastlane/screenshots/en-CA/`.

### Running a capture

```sh
cd ios && bundle exec fastlane snapshot
```

This launches the showcase UI (`AppStoreScreenshotShowcaseView`) with the
`-AppStoreScreenshots` and `-AppStoreScreenshotPage <0-5>` launch arguments on
each device. The showcase is fully offline — it uses bundled `NSLocalizedString`
keys and Color literals with no backend dependency.

On iPad simulators the showcase automatically renders a two-column layout
(headline/subtitle on the left, content card on the right) via
`horizontalSizeClass == .regular`, producing screenshots that are visually
distinct from the phone captures.

### Output

Fastlane writes PNGs named `<Device>-<scene>.png` into
`ios/fastlane/screenshots/en-CA/`. The `clear_previous_screenshots(true)`
Snapfile directive removes stale files before each run.

### Refreshing the App Store upload set

Copy the Fastlane output into the delivery directory:

```sh
cp -f ios/fastlane/screenshots/en-CA/*.png docs/marketing/screenshots/
```

### Manual single-device capture

To capture a single device outside Fastlane:

```sh
xcodebuild test \
  -project ios/epac.xcodeproj \
  -scheme epac \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -only-testing:epacUITests/AppStoreScreenshotTests/testCaptureAppStoreScreenshotSources
```

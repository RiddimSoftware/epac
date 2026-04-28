# Evidence Workflows

EPAC uses the shared `evidence` package and CLI for repeatable local proof artifacts.

## Configuration

The root `.evidence.toml` defines the app scheme, bundle ID, simulator, evidence directory, screenshot targets, and App Preview defaults.

## Raw App Store Captures

Run the UI test capture plan from `ios/`:

```sh
APPSTORE_SCREENSHOT_DIR=/tmp/epac-appstore-screenshots xcodebuild test -project epac.xcodeproj -scheme epac -destination 'platform=iOS Simulator,name=EPAC App Store 16 Pro Max' -only-testing:epacUITests/epacUITests/testCaptureAppStoreScreenshotSources
```

The test uses `Evidence.ScreenshotPlan` with the app's `-AppStoreScreenshots` launch mode.

## Resizing

From the repository root:

```sh
scripts/marketing/render_app_store_screenshots.sh /tmp/epac-appstore-screenshots docs/marketing/screenshots
```

The script preserves the existing input/output contract and delegates each resize to `evidence resize --target 6.9`.

## Synthetic Marketing Renders

EPAC-local scene specs live under `docs/marketing/app-store/evidence-scenes/`.

```sh
scripts/evidence/run-evidence.sh render-marketing --scene docs/marketing/app-store/evidence-scenes/epac-109/01-parliament-in-your-pocket.json --svg /tmp/epac-109.svg --output /tmp/epac-109.png
scripts/evidence/run-evidence.sh render-marketing --scene docs/marketing/app-store/evidence-scenes/epac-111/01-your-mp-voted-last-night.json --svg /tmp/epac-111.svg --output /tmp/epac-111.png
```

The current JSON specs intentionally represent the reusable renderer path rather than pixel-matching the older Python output. Keep app-specific copy, colors, and source text in this repository.

## App Preview

```sh
scripts/marketing/record-app-preview.sh
```

The script still records the live simulator flow, then delegates final H.264/no-audio encoding to `evidence record-preview` with 886x1920, 30fps, and <=30s defaults.

## PR Build Evidence

```sh
scripts/evidence/run-evidence.sh capture-evidence --ticket EPAC-123
```

This writes `docs/build-evidence/EPAC-123-running.png` and prints a raw GitHub Markdown image URL for PR descriptions.

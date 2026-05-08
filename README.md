# epac

**Canada's Parliament, in your pocket — an iPhone app for tracking MPs, bills, votes, debates, expenses, and lobbying activity from official Canadian government sources.**

<p align="center">
  <a href="https://epac.riddimsoftware.com/">
    <img src="website/ss-1-light.png" alt="epac iPhone screenshot showing the app's parliamentary tracking interface" width="320">
  </a>
</p>

<p align="center">
  <a href="https://apps.apple.com/ca/app/epac/id1224459142">
    <img src="website/app-store.svg" alt="Download on the App Store" height="52">
  </a>
</p>

<p align="center">
  <a href="https://epac.riddimsoftware.com/">Homepage</a>
  ·
  <a href="https://apps.apple.com/ca/app/epac/id1224459142">App Store</a>
</p>

## What it does and why

`epac` turns the House of Commons record into something more readable than a feed of PDFs, XML, and committee pages. The app lets Canadians follow what MPs actually do between elections: how they vote, what bills they sponsor, what gets said in debate, and which topics are active in Parliament.

One of its core ideas is **Hansard as chat**. Instead of treating parliamentary debate as a wall of transcript text, epac presents speeches in a conversational format that is faster to scan on a phone while still staying grounded in the official record. The goal is not commentary or partisanship; it is a civic tool that makes primary-source parliamentary data easier to browse, search, and verify.

## Architecture

This repository is intentionally polyglot because each part of the product does a different job:

- **SwiftUI + SwiftData (`ios/`)** — the iPhone app, widgets, app clip, local persistence, and product UI.
- **Go services (`backend/`)** — API endpoints, ingestion workers, and backend jobs that fetch, normalize, and serve parliamentary data.
- **Python tools (`backend/` and `scripts/`)** — focused ingestion utilities, release helpers, localization checks, and evidence/marketing tooling.
- **HTML/CSS/JS (`website/`)** — the public website, landing pages, topic pages, and App Store support web surfaces.
- **Data snapshots (`data/` and bundled app assets)** — source-derived files that help feed the app experience.

Together, those layers support the same product loop: gather authoritative public data, structure it, and deliver it in a mobile experience that makes Parliament easier to follow.

## Build and run

### iOS app

Requirements:

- Xcode with iOS 17+ simulator support
- macOS

Open the project in Xcode:

```bash
open ios/epac.xcodeproj
```

Then select the `epac` scheme and run it in the simulator.

Alternatively, build from the command line using the provided `ios/Makefile`. This path is recommended for first-time contributors as it automatically finds an available simulator.

First, install [xcbeautify](https://github.com/cpisciotta/xcbeautify):

```bash
brew install xcbeautify
```

Then build and run:

```bash
cd ios
make build      # Build the app
make simulator  # Build and deploy to an available simulator
```

`make simulator` automatically targets an available iPhone simulator. To target a specific one, you can override `SIM_NAME`:

```bash
cd ios && make simulator SIM_NAME='iPhone 16'
```

If you prefer to use `xcodebuild` directly, you can list available simulators with `xcrun simctl list devices available` and then specify one:

```bash
cd ios
xcodebuild -project epac.xcodeproj -scheme epac -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR_NAME' build
```

### Backend and tooling prerequisites

Requirements:

- Go 1.24+
- Python 3

Install the repo's Python dev dependency:

```bash
pip install -r requirements-dev.txt
```

Useful local checks:

```bash
cd backend/search && go test ./...
cd backend/hansard-backfill && go test ./...
python3 backend/cabinet/cabinet_ingest.py --dry-run
```

The iOS app is the main product surface; the backend services and scripts exist to ingest, shape, and publish the public parliamentary data that the app depends on.

## Contribute

Issues and pull requests are welcome. Start with [CONTRIBUTING](CONTRIBUTING.md), then read the [Code of Conduct](CODE_OF_CONDUCT.md) and [Security Policy](SECURITY.md).

PRs may receive an automated first-pass review; humans review and merge.

## License

Distributed under the [MIT License](LICENSE).

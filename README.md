# epac

`epac` is an iPhone app for following Canada's House of Commons from official
public records: Hansard debates, MPs, bills, votes, expenses, lobbying activity,
and related civic data.

It started as a simple idea: make Hansard feel like a group chat. Instead of
reading parliamentary debate as long transcript pages, epac presents speeches as
a phone-native conversation that is easier to scan while staying grounded in the
source record.

- App Store: [epac on the App Store](https://apps.apple.com/ca/app/epac/id1224459142)
- Website: [epac.riddimsoftware.com](https://epac.riddimsoftware.com/)

## What This Repo Contains

This is a small public app with a disproportionately large codebase because it
owns most of its data path:

- `ios/` — SwiftUI iPhone app, app clip, widgets, Watch surfaces, UI tests, and
  release assets.
- `backend/` — Go services and workers for parliamentary data APIs, ingestion,
  search, and publishing.
- `scripts/` — data, localization, release, and agent-intake utilities.
- `website/` — public website, support pages, and topic/riding pages.
- `docs/` — architecture notes, product specs, evidence, design, release, and
  operational documentation.

The product is non-partisan. App-visible claims should trace back to official
government, parliamentary, or open-data sources.

## Local Development

Open the iOS app in Xcode:

```sh
open ios/epac.xcodeproj
```

Build from the command line:

```sh
cd ios
make build
```

Run backend checks for a service:

```sh
cd backend/member-speeches
go test ./...
```

Some backend services expect local AWS, data, or staging configuration. The iOS
app is the main product surface; backend tools exist to ingest, normalize, and
publish the public records it uses.

## Contributing

The preferred public contribution path is a spec, not a drive-by patch. Clone
the repo, open it in your coding agent, and turn the idea or bug report into:

```text
proposals/<short-slug>/SPEC.md
```

A useful spec explains the problem, the source data involved, expected product
behavior, validation evidence, and open questions. Maintainers can then route
accepted specs into the Riddim Software Factory for implementation, review,
evidence generation, and release.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the current contribution rules.

## License

MIT. See [LICENSE](LICENSE).

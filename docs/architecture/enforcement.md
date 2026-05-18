# Architecture Enforcement

EPAC's Dependency Rule is enforced by lightweight CI gates. These checks keep
application policy free of framework details and keep the manifest contract
shared between backend publishers and the iOS consumer.

## Backend Dependency Rule

CI runs `scripts/ci/check_go_dependency_rule.sh` from `backend-pr.yml`.
The rule scans `backend/*/internal/usecase/*.go` and allows only:

- Go standard library imports.
- The Lambda module's own `internal/` packages.

The checked-in `backend/.go-arch-lint.yml` mirrors the intended architecture
shape for `go-arch-lint`-style tooling. The repo script is the CI gate because
this backend is a multi-module tree and the rule needs the owning module for
each Lambda.

Failure remediation:

> Use case packages must not import frameworks. Move framework usage to internal/adapter/. See docs/architecture/use-case-catalog.md.

## iOS Application Layer Imports

SwiftLint runs with `.swiftlint.yml` in `pr-build.yml`. The
`application_layer_framework_imports` custom rule fails any file under
`ios/epac/Application/` that imports `Foundation.URLSession`, `UIKit`,
`SwiftData`, or `SwiftUI`.

Failure remediation:

> This file is in the Application layer. Framework imports must move to ios/epac/Util/ or ios/epac/Views/. See docs/architecture/use-case-catalog.md.

## Manifest Contract

The backend manifest package owns the cross-language schema at
`backend/manifest/manifest.schema.json` and the generated sample at
`backend/manifest/testdata/manifest.sample.json`.

CI validates the contract in three ways:

- `backend/manifest` decodes the sample as `manifest.Manifest`.
- `backend/manifest` validates the sample against `manifest.schema.json`.
- `ios/epacTests/ArtifactServiceTests.swift` decodes the same sample as
  `ArtifactManifest`.

Failure remediation: update the Go writer, JSON Schema, sample manifest, and
iOS `ArtifactManifest` together when the manifest envelope changes.

## Use-Case Catalog Drift

CI runs `scripts/ci/check_catalog_drift.sh` from `backend-pr.yml`. It reads the
`Current implementation` blocks in `docs/architecture/use-case-catalog.md` and
fails if any listed source path no longer exists.

Failure remediation: update the catalog entry in the same PR that creates,
renames, removes, or materially changes a cataloged implementation path.

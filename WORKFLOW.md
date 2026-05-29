---
workflow_template:
  managed: true
  source_ref: templates/WORKFLOW.template.md
  version: sha256:a2b3385d92813396c4cab52753fa924d69a79a5437115a19ae403d2803a8a4d9
  managed_block_sha256: 57ea2da2ae0b7a838d894600c56d1e3e99cc759c1099349362e32523eff50a3b
  repo_name: epac
  verification_command: 'Run `cd ios && make build`. See the Verification Expectations section for area-specific commands.'
  disabled_prompt_instruction_ids: []
extends: ../agent-config/symphony/shared.yml
tracker:
  project_slug: EPAC
repositories:
  - epac

server:
  port: 4781
---

<!-- symphony-workflow:local-section id=purpose -->
## Purpose

This repository is the epac implementation repository. It contains the SwiftUI
and SwiftData iOS app, backend services and data pipelines, the static website,
release metadata, and product documentation for Canada's House of Commons
Hansard civic-engagement experience.

Symphony work here should produce product changes, backend changes, website
changes, App Store metadata/assets, release-support changes, or repo
maintenance that belongs in `RiddimSoftware/epac`.

If the issue requires changes outside `RiddimSoftware/epac`, stop and leave a
Linear comment asking for the ticket to be split or rerouted.
<!-- /symphony-workflow:local-section -->

<!-- symphony-workflow:local-section id=epac_repository_rules -->
## Repository Rules

Additional rules beyond the standard repository rules above:

- All user-facing civic content displayed by the app must trace to authoritative
  source data. Do not invent, summarize, or rewrite parliamentary content with
  LLM-generated text.
- Preserve the product voice and positioning in `docs/brand/brand-brief-v1.md`.
- Adding or changing a backend endpoint requires updating
  `backend/openapi/openapi.json` in the same PR.
- Do not upload TestFlight builds, submit App Store changes, or run production
  deployment commands unless the issue explicitly authorizes that release or
  infrastructure action. When a human gate is required, leave a detailed Linear
  comment and stop.
<!-- /symphony-workflow:local-section -->

<!-- symphony-workflow:local-section id=verification_expectations -->
## Verification Expectations

- For `WORKFLOW.md` changes, validate from `/Users/sunny/code/autopilot` with
  `swift run symphonyd --validate-only /Users/sunny/code/epac/WORKFLOW.md`.
- For iOS app changes, run `cd ios && make build`. If the Makefile dependencies
  are unavailable, run this equivalent command and report the substitution:
  `cd ios && xcodebuild -project epac.xcodeproj -scheme epac -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR_NAME' build`.
- For changed iOS ViewModel, service, manager, or model logic, add or update
  unit tests and run `cd ios && make test` or the narrowest equivalent
  `xcodebuild test` command.
- For Swift or localization changes, run `swiftlint --strict` and
  `python3 scripts/localization/check_localizations.py --github-warnings` when
  those tools are available.
- For backend Go service changes, run
  `cd backend/<service> && go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out`.
- For backend API changes, update `backend/openapi/openapi.json` and run the
  affected service tests, including `backend/openapi` when the contract changes.
- For UI, App Store screenshot, or marketing asset changes, run the documented
  screenshot/evidence flow and include the resulting assets or links in the PR.
<!-- /symphony-workflow:local-section -->
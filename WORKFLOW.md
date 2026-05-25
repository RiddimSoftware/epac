---
workflow_template:
  managed: true
  source_ref: templates/WORKFLOW.template.md
  version: sha256:f3a44a62dff61239f3bf0b6a8738c57dcb111e94a5f7a29a1d0d0dc2e7c4d17f
  managed_block_sha256: 7300e66231d5efa71343ace1d0775005f18198a0a970c712dd8a9a8f90bc8ee8
extends: ../agent-config/symphony/shared.yml
tracker:
  project_slug: EPAC
agent:
  max_agents: 4
  per_tick_dispatch_ceiling: 4
polling:
  interval_ms: 15000

server:
  port: 4781
reviewer:
  enabled: false
---
# epac Symphony Workflow

You are implementing Linear issue {{ issue.identifier }} for epac: {{ issue.title }}.

State: {{ issue.state }}
Estimate: {{ issue.estimate }}
Attempt: {{ attempt }}

Labels:
{% for label in issue.labels %}
- {{ label }}
{% endfor %}

Description:
{{ issue.description }}

Follow the repository instructions in AGENTS.md and CLAUDE.md when present.
Read the Symphony Handoff Context at the top of this prompt before acting. Its
mode tells you whether this is fresh work, resumed worktree work, or an
existing PR fix.

Repository rules:
- Symphony starts you in an issue-specific git worktree. Do not edit the root checkout or create another worktree unless the issue explicitly requires it.
- Keep the root checkout on main if you inspect it.
- Use the current branch from the handoff context.
- If the handoff mode is `fix_existing_pr` or `resumed`: push fixes to the existing PR branch. Do not open a new PR under any circumstances.

PR handoff contract:
- Create at least one commit for the issue before handoff.
- Confirm the branch is clean with `git status --porcelain`.
- Refresh the repo root with `git fetch origin main` and rebase the worktree branch onto `origin/main`.
- Push the branch to origin before opening the PR.
- Fresh run: open exactly one PR with `gh pr create --label autonomous`.
- Resumed or fix_existing_pr run: push to the existing branch. Do not create a new PR.
- Use the PR title format `[{{ issue.identifier }}]: <short description>`.
- Include verification evidence and any skipped checks with reasons in the PR body.

<!-- symphony-workflow:local-section id=purpose -->
## Purpose

This repository is the epac implementation repository. It contains the SwiftUI
and SwiftData iOS app, backend services and data pipelines, the static website,
release metadata, and product documentation for Canada's House of Commons
Hansard civic-engagement experience.

Symphony work here should produce product changes, backend changes, website
changes, App Store metadata/assets, release-support changes, or repo
maintenance that belongs in `RiddimSoftware/epac`.
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
<!-- /symphony-workflow:local-section -->

<!-- symphony-workflow:local-section id=self_review -->
## Self-Review

After verification passes, read `git diff origin/main...HEAD` in full. For each acceptance criterion in the issue, confirm there is corresponding code. Flag and fix anything that looks like a missed edge case, incorrect assumption, or incomplete implementation. Use your existing context — do not re-read files speculatively.

Open the PR only after this pass is clean.
<!-- /symphony-workflow:local-section -->

<!-- symphony-workflow:local-section id=pr_submission -->
## PR Submission

There is no separate reviewer step. Once the self-review pass is clean and verification passes, open the PR and stop. CI gates the merge: `pr-build` is the required status check. `set-automerge.yml` arms squash automerge on PR open — GitHub merges automatically when `pr-build` passes.

- Open the PR with `gh pr create`
- Do not wait for CI, review, or merge confirmation inside the model session.
- Stop the session after opening the PR
<!-- /symphony-workflow:local-section -->

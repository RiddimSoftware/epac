---
workflow_template:
  managed: true
  source_ref: templates/WORKFLOW.template.md
  version: sha256:94cd413332b5cb8007ffa9a39dca419e2c5f40ecc9bbf8047198a38e3c400c1e
  managed_block_sha256: c8bb0b220ac17d6140f93e4d2c99043a29314cf3082080d0d7eb96d9d94ad8a2
extends: ../agent-config/symphony/shared.yml
tracker:
  project_slug: EPAC
repositories:
  - slug: RiddimSoftware/epac
    local_path: /Users/sunny/code/epac
    capabilities:
      - edit
      - review
reviewer:
  enabled: true
  reserved_agent_slots: 4
developer:
  pr_fix_reserved_agent_slots: 4
agent:
  max_concurrent_agents: 10
server:
  port: 4781
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

Before editing files:
- Confirm {{ issue.identifier }} is In Progress in Linear.
- Add a Linear comment with the selected provider, workspace path, and start time.
- If the issue is not In Progress, stop and report the blocker.

Repository rules:
- Symphony starts you in an issue-specific git worktree. Do not edit the root checkout or create another worktree unless the issue explicitly requires it.
- Keep the root checkout on main if you inspect it.
- Keep each change scoped to one Linear issue and one pull request.
- Treat the handoff context's routing decision as binding when present.
- Use the current branch from the handoff context.
- If the routing decision points at another repository, or if you can prove the routing evidence is wrong, stop and leave a blocking Linear comment instead of switching repos or opening a PR elsewhere.
- If the handoff mode is `fix_existing_pr` or `resumed`: push fixes to the existing PR branch. Do not open a new PR under any circumstances.
- If the issue estimate is missing in this prompt, treat it as the standard 8 complexity tier and mention the missing estimate in the PR body and a Linear comment.

PR ownership lifecycle:
Your responsibility is to own the PR from creation until one of these terminal
conditions:
- Symphony reviewer mode only acts on PRs labeled `autonomous`: it posts review
  comments as `riddim-reviewer-bot[bot]` and, on approval, arms GitHub's native
  auto-merge.
- GitHub automerge completes the merge — stop and leave a summary comment in
  Linear.
- A reviewer blocks the PR with requested changes — push fixes and update your
  Linear blocker comment.
- A human-gated check requires manual intervention — leave a detailed Linear
  comment with the exact action needed and stop.

Do not manually merge the PR. GitHub automerge owns all merges. Your role is to
push a shippable branch and keep the PR unblocked.

PR handoff contract:
- Create at least one commit for the issue before handoff.
- Confirm the branch is clean with `git status --porcelain`.
- Refresh the repo root with `git fetch origin main` and rebase the worktree branch onto `origin/main`.
- Push the branch to origin before opening the PR.
- Use plain `gh`; Symphony has already set `RIDDIM_DEV_BOT_GH=1` and verified the `gh agent-bot status` preflight so `gh pr create` opens as `riddim-developer-bot[bot]`.
- Fresh run: open exactly one PR with `gh pr create --label autonomous`.
- Fresh run: include `Reviewer-Boundary: review-only` in the PR body so the legacy developer-fix workflow skips this PR and Symphony's WakeDeveloperForPRAction owns fix cycles.
- Resumed or fix_existing_pr run: push to the existing branch. Do not create a new PR.
- Use the PR title format `[{{ issue.identifier }}]: <short description>`.
- Include verification evidence and any skipped checks with reasons in the PR body.

Durable state for resume:
After opening or updating the PR, leave a Linear comment with:
- Implementation notes and key decisions made.
- Verification evidence (commands run and pass/fail results).
- Tradeoffs or known limitations.
- Any blockers or follow-up work required.

This comment is the resume packet. A fresh agent session rebuilds context from
it, so write it as a self-contained handoff — not a conversation summary.

After posting the resume comment, stop. Do not wait for review, CI, automerge,
or human confirmation.

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

Verification expectations:
- Run `cd ios && make build`. See the Verification Expectations section for area-specific commands.
- Report any verification that could not run with the exact command and reason.
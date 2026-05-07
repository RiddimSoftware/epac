---
tracker:
  kind: linear
  endpoint: https://api.linear.app/graphql
  api_key: $LINEAR_API_KEY
  api_key_aws_secret:
    secret_id: linear/api-key
    profile: riddim-agent
    region: us-east-1
  project_slug: EPAC
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Canceled
    - Cancelled
    - Duplicate
  stale_claim_reconciliation:
    enabled: false
    source_state: In Progress
    target_state: Todo
    idle_after_ms: 86400000
    require_no_open_pr: true
    require_no_local_worker: true
polling:
  interval_ms: 30000
repositories:
  - slug: RiddimSoftware/epac
    local_path: /Users/sunny/code/epac
    capabilities:
      - edit
      - review
reviewer:
  enabled: true
  polling_interval_ms: 30000
  bot_identity_wrapper_path: /Users/sunny/code/agent-config/bin
  opener_allowlist:
    - riddim-developer-bot
    - app/riddim-developer-bot
workspace:
  root: ./.symphony/workspaces
  repository_root: .
  base_branch: main
  branch_prefix_template: claude
  use_git_worktree: true
  require_clean_root: true
  reset_root_before_dispatch: true
hooks:
  timeout_ms: 60000
agent:
  providers:
    - name: codex
      weight: 1
    - name: claude
      weight: 1
    - name: gemini
      weight: 1
  max_concurrent_agents: 1
  max_turns: 20
  max_retry_backoff_ms: 300000
  max_resume_attempts: 5
  max_fix_attempts: 3
  max_concurrent_agents_by_state:
    In Progress: 1
    Todo: 1
  github_bot:
    enabled: true
    path_prefix: /Users/sunny/code/agent-config/bin
    aws_profile: riddim-agent
    expected_login: riddim-developer-bot[bot]
    git_author_name: riddim-developer-bot
    git_author_email: developer-bot@riddimsoftware.com
  reviewer_bot:
    enabled: true
    path_prefix: /Users/sunny/code/agent-config/bin
    aws_profile: riddim-agent
    expected_login: riddim-reviewer-bot[bot]
    git_author_name: riddim-reviewer-bot
    git_author_email: reviewer-bot@riddimsoftware.com
codex:
  command: codex app-server
  approval_policy:
    mode: never
  thread_sandbox:
    mode: danger-full-access
  turn_sandbox_policy:
    mode: danger-full-access
  turn_timeout_ms: 3600000
  read_timeout_ms: 5000
  stall_timeout_ms: 300000
claude:
  command: claude --dangerously-skip-permissions -p
  turn_timeout_ms: 3600000
gemini:
  command: gemini
  approval_mode: yolo
  skip_trust: true
  turn_timeout_ms: 3600000
server:
  port: 4781
---
# epac Symphony Workflow

You are coordinating Linear issue {{ issue.identifier }} for EPAC: {{ issue.title }}.

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

## Purpose

This repository is the epac implementation repository. It contains the SwiftUI
and SwiftData iOS app, backend services and data pipelines, the static website,
release metadata, and product documentation for Canada's House of Commons
Hansard civic-engagement experience.

Symphony work here should produce product changes, backend changes, website
changes, App Store metadata/assets, release-support changes, or repo
maintenance that belongs in `RiddimSoftware/epac`.

## Repository Rules

- The default and only target repository for EPAC implementation work is
  `RiddimSoftware/epac`.
- Keep each change scoped to one Linear issue, one target repository, and one
  pull request.
- Treat the handoff context's routing decision as binding when present.
- If the routing decision points at another repository, or if you can prove the
  routing evidence is wrong, stop and leave a blocking Linear comment instead
  of switching repos or opening a PR elsewhere.
- If the issue requires changes outside `RiddimSoftware/epac`, stop and leave a
  Linear comment asking for the ticket to be split or rerouted.
- If the handoff mode is `fix_existing_pr` or `resumed`, push fixes to the
  existing PR branch. Do not open a new PR.
- If the issue estimate is missing in this prompt, treat it as the standard 8
  complexity tier and mention the missing estimate in the PR body and a Linear
  comment.
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

## Repository Discipline

Symphony starts you in an issue-specific git worktree. Do not inspect, edit, or
run commands from the root checkout. Do not create another worktree unless the
issue explicitly requires it. Use the current branch from the handoff context.

## Handoff Expectations

When implementation is needed, the repo-scoped worker should:

- make the smallest coherent change that satisfies the issue;
- create at least one commit for the issue before handoff;
- confirm the branch is clean with `git status --porcelain`;
- from this worktree, run `git fetch origin main` and rebase the current branch
  onto `origin/main`;
- push the branch to origin before opening the PR;
- use plain `gh`; Symphony has already set `RIDDIM_DEV_BOT_GH=1` and verified
  the `gh agent-bot status` preflight so `gh pr create` opens as
  `riddim-developer-bot[bot]`;
- fresh run: open exactly one PR with `gh pr create --label autonomous`;
- fresh run: include `Reviewer-Boundary: review-only` in the PR body so the
  legacy developer-fix workflow skips this PR and Symphony's
  WakeDeveloperForPRAction owns fix cycles;
- resumed or fix_existing_pr run: push to the existing branch and do not create
  a new PR;
- use the PR title format `[{{ issue.identifier }}]: <short description>`;
- include verification evidence and any skipped checks with reasons in the PR
  body. For UI or screenshot changes, include before/after screenshots or a
  short screen recording.

## PR Ownership Lifecycle

Your responsibility is to own the PR from creation until one of these terminal
conditions:

- GitHub automerge completes the merge: stop and leave a summary comment in
  Linear.
- A reviewer blocks the PR with requested changes: push fixes and update your
  Linear blocker comment.
- A human-gated check requires manual intervention: leave a detailed Linear
  comment with the exact action needed and stop.

Do not manually merge the PR. GitHub automerge owns all merges. Your role is to
push a shippable branch and keep the PR unblocked.

## Durable State For Resume

After opening or updating the PR, leave a Linear comment with:

- Implementation notes and key decisions made.
- Verification evidence, including commands run and pass/fail results.
- Screenshots or recordings for UI, screenshot, or App Store asset changes.
- Tradeoffs or known limitations.
- Any blockers or follow-up work required.

This comment is the resume packet. A fresh agent session rebuilds context from
it, so write it as a self-contained handoff, not a conversation summary.

After posting the resume comment, stop. Do not wait for review, CI, automerge,
or human confirmation.

## Verification Expectations

- For `WORKFLOW.md` changes, validate from `/Users/sunny/code/autopilot` with
  `swift run symphonyd --validate-only /Users/sunny/code/epac/WORKFLOW.md`.
- For iOS app changes, run `cd ios && make build`. If the Makefile dependencies
  are unavailable, run this equivalent command and report the substitution:
  `cd ios && xcodebuild -project epac.xcodeproj -scheme epac -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`.
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
- Report any verification that could not run with the exact command and reason.

## Bot Environment and Runbook

This workflow uses the org-standard developer-bot and reviewer-bot environment:

- `agent.github_bot.enabled: true`
- `agent.github_bot.path_prefix: /Users/sunny/code/agent-config/bin`
- `agent.reviewer_bot.enabled: true`
- `agent.reviewer_bot.path_prefix: /Users/sunny/code/agent-config/bin`
- `agent.github_bot.aws_profile: riddim-agent`
- expected developer login: `riddim-developer-bot[bot]`
- expected reviewer login: `riddim-reviewer-bot[bot]`

Validate and run this workflow with:

- `cd /Users/sunny/code/autopilot && swift run symphonyd --validate-only /Users/sunny/code/epac/WORKFLOW.md`
- `cd /Users/sunny/code/autopilot && swift run symphonyd /Users/sunny/code/epac/WORKFLOW.md --once`
- `cd /Users/sunny/code/autopilot && swift run symphonyd /Users/sunny/code/epac/WORKFLOW.md`

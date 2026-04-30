# Agent Loop Enrollment — epac

This document records the repo-local enrollment work for `epac` as the first consumer of the autonomous PR loop hosted in `RiddimSoftware/riddim-release`.

## What lives in epac

- `.github/workflows/agent-loop.yml` is the thin trigger wrapper.
- `.github/CODEOWNERS` is the active CODEOWNERS file for this repo.
- Branch protection and org-secret repository access are configured in GitHub settings, not committed to the repo.

The wrapper intentionally keeps behavior small: it filters GitHub events, passes the trigger context into reusable workflows, and inherits org-scoped secrets. Developer/reviewer prompts, guard logic, retry handling, and merge behavior stay centralized in `riddim-release`.

## Trigger contract

The wrapper calls `RiddimSoftware/riddim-release/.github/workflows/developer.yml@main` for:

- `issues.labeled` when the applied label is `agent:build`, using `trigger_type: issue_labeled`.
- `pull_request_review.submitted` when `reviewer-bot` requests changes, using `trigger_type: changes_requested`.

The wrapper calls `RiddimSoftware/riddim-release/.github/workflows/reviewer.yml@main` for:

- `pull_request.opened`, `pull_request.synchronize`, and `pull_request.ready_for_review` when the PR author is `developer-bot` and the sender is not `reviewer-bot`.

All paths short-circuit when `agent:pause` or `agent:needs-human` is present on the target issue/PR.

## Required labels

Create these labels on `epac` before enabling the loop:

- `agent:build`
- `agent:pause`
- `agent:needs-human`
- `agent:attempt-1`
- `agent:attempt-2`
- `agent:attempt-3`
- `agent:rebase-attempt-1`
- `agent:rebase-attempt-2`
- `agent:rebase-attempt-3`
- `agent:codeowners-veto`
- `autonomous`
- `automate`

Use the riddim-release enrollment script once it is merged:

```bash
scripts/enroll-repo.sh RiddimSoftware/epac
```

## Required org secrets

The wrapper uses `secrets: inherit`. Confirm the following org secrets are configured with selected-repository access to `epac`:

- `CLAUDE_CODE_OAUTH_TOKEN`
- `DEV_BOT_PAT`
- `REVIEWER_BOT_PAT`

If the reusable workflows migrate from PATs to GitHub App installation tokens, also grant `epac` access to the corresponding App ID/private-key secrets and update this document in the same PR.

## Branch protection settings for `main`

Navigate to: **Settings -> Branches -> Branch protection rules -> Edit (main)**

Enable **Require status checks to pass before merging** and add:

| Check name | Source |
|---|---|
| `build` | Existing iOS CI |
| `test` | Existing iOS CI |
| `swiftlint` | Existing iOS CI |
| `reviewer-agent-passed` | Agent-loop reviewer workflow |

Also enable **Require branches to be up to date before merging**.

Enable these pull request review settings:

- Require a pull request before merging.
- Require 1 approving review.
- Dismiss stale pull request approvals when new commits are pushed.
- Require review from Code Owners.
- Require conversation resolution before merging.

Enable these repository settings outside branch protection:

- Allow auto-merge.
- Automatically delete head branches.
- Restrict direct pushes to `main` to repository admins/owners only.

## CODEOWNERS coverage

GitHub uses `.github/CODEOWNERS` before a root-level `CODEOWNERS`, so `.github/CODEOWNERS` is the canonical owner file for epac.

The active file routes every PR to `@sunnypurewal` while the team is solo and explicitly protects release/configuration surfaces such as `.github/`, `fastlane/`, `ios/fastlane/`, signing/config files, Xcode project files, entitlements, privacy manifests, and secret-shaped files.

For the agent loop, this matters because E10's CODEOWNERS veto treats human-owned conflict paths as non-autonomous during rebase/conflict recovery.

## Verification checklist

After branch protection and secrets are configured, run these smoke tests:

1. Positive path: create a throwaway issue, label it `agent:build`, confirm the developer workflow opens a PR, confirm the reviewer workflow posts a verdict, and confirm auto-merge proceeds only after CI is green.
2. Negative path: open a PR without `reviewer-agent-passed`; confirm the merge button is blocked.
3. Pause path: apply `agent:pause` to an eligible PR; confirm the reviewer/developer jobs skip.
4. Human path: apply `agent:needs-human`; confirm automation does not run again until the label is removed.

Do not run E6 pilot evidence until the shared riddim-release workflows, secrets, labels, branch protection, and this wrapper are all merged/configured.

# Agent Loop Enrollment — epac

This document describes the branch protection settings that must be applied manually in the GitHub UI to complete enrollment of `epac` in the autonomous PR loop.

## Why manual?

GitHub's branch protection API requires admin-level tokens. Automating this fully would require storing elevated credentials in CI, which is undesirable for a production-critical repo. Apply these settings once; they are stable.

## Branch protection settings for `main`

Navigate to: **Settings → Branches → Branch protection rules → Edit (main)**

### Required status checks

Enable "Require status checks to pass before merging" and add:

| Check name | Source |
|---|---|
| `build` | Existing iOS CI |
| `test` | Existing iOS CI |
| `swiftlint` | Existing iOS CI |
| `reviewer-agent-passed` | Added by agent-loop reviewer workflow |

Also enable **"Require branches to be up to date before merging"**.

### Pull request reviews

- **Require a pull request before merging**: enabled
- **Required approving reviews**: 1
- **Dismiss stale pull request approvals when new commits are pushed**: enabled (non-negotiable — prevents stale APPROVE from shipping unreviewed code to TestFlight)
- **Require review from Code Owners**: enabled

### Additional settings

- **Require conversation resolution before merging**: enabled
- **Restrict who can push to matching branches**: enabled (restrict direct pushes to `main`; admins included where possible)

### Repository settings (outside branch protection)

- **Allow auto-merge**: enabled (Settings → General → Pull Requests → Allow auto-merge)
- **Automatically delete head branches**: enabled

## Verification checklist

After applying the above settings, run the following smoke tests:

1. **Positive path**: Create a throwaway issue, label it `agent:build`. Confirm the developer workflow fires and opens a PR. Confirm the reviewer workflow fires on the PR and posts approval. Confirm auto-merge fires once CI is green.

2. **Negative path**: Open a PR without `reviewer-agent-passed` status check passing. Confirm the merge button is blocked. This is critical — without it, a misconfigured rule allows agent-only merges to ship to TestFlight unreviewed.

## Secrets access

The `agent-loop.yml` workflow uses `secrets: inherit`. Confirm that the org secrets `CLAUDE_CODE_OAUTH_TOKEN`, `DEV_BOT_PAT`, and `REVIEWER_BOT_PAT` are configured with access to the `epac` repository:

**Settings → Secrets and variables → Actions → (each secret) → Repository access**

## CODEOWNERS

`CODEOWNERS` at the repo root protects the following paths (requiring review from `@RiddimSoftware/owners`):

- `.github/workflows/` — CI/CD pipeline changes
- `.github/scripts/` — automation scripts
- `CODEOWNERS` — this file itself
- `fastlane/` — release automation
- `Gemfile` — Ruby dependencies for Fastlane
- `ios/` — iOS source and release configuration

Add or remove paths here as the codebase evolves. The `ios/` coverage is intentionally broad; tighten to specific subdirectories (e.g. `ios/fastlane/`, `ios/*.xcconfig`) if the owners team prefers narrower scope.

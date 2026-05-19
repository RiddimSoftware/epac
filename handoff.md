## Implementation notes
- EPAC-1921 was re-checked in Linear and remains active: status `In Progress`, status type `started`, estimate `8 Points`, `archivedAt: null`, `completedAt: null`, `canceledAt: null`, `updatedAt: 2026-05-19T01:23:02.376Z`.
- No new source implementation changes were made in this pass because the ticket's explicit pre-PR CloudWatch gate still fails.
- Current branch is `symphony/epac-1921-backend-delete-unused-lambdas-search-live-status`; the worktree currently only has this `handoff.md` update pending and has 2 commits ahead of `origin/main`.
- Important branch state: the existing ahead commits are `fd728ce4 [EPAC-1921]: WIP — recovered from parent_killed` and `03297471 [EPAC-1921]: WIP — recovered from parent_killed`. Prior diff inspection showed broad changes across GitHub workflows, backend services, infrastructure, iOS, docs, scripts, and `handoff.md`. That scope appears wider than EPAC-1921 and should be reconciled before any PR is opened. I did not revert or rewrite it.
- Previous inspection found the EPAC-1921 deletion is not limited to the four Lambda directories: it also affects `backend/go.work`, OpenAPI, API Gateway/IAM/log group infrastructure, smoke checks, and tests.
- Previous inspection found `backend/live-status` also serves `/calendar/house.ics` and `/api/v1/calendar/house.ics`; Terraform routes `house_calendar` and `house_calendar_legacy` point at that function.

## Verification evidence
- Linear issue check on 2026-05-19 confirmed EPAC-1921 remains active: `status: In Progress`, `statusType: started`, `archivedAt: null`, `completedAt: null`, `canceledAt: null`, `updatedAt: 2026-05-19T01:23:02.376Z`. The active-state check was completed through Linear GraphQL using the project API credential from AWS Secrets Manager.
- Local branch evidence from this pass:
  - `git status --porcelain` returned `M handoff.md`.
  - `git rev-list --count origin/main..HEAD` returned `2`.
  - Current branch is `symphony/epac-1921-backend-delete-unused-lambdas-search-live-status`.
- CloudWatch command run with `AWS_PROFILE=riddim-agent`, region `us-east-1`, namespace `AWS/Lambda`, metric `Invocations`, dimensions `FunctionName=<name>`, period `86400`, statistics `Sum`.
- CloudWatch window checked: `2026-05-12T01:35:32Z` to `2026-05-19T01:35:32Z`.
- CloudWatch results:
  - `search`: `2026-05-13T01:35:00+00:00 7.0`, `2026-05-14T01:35:00+00:00 5.0`.
  - `live-status`: `2026-05-14T01:35:00+00:00 12.0`, `2026-05-15T01:35:00+00:00 1.0`, `2026-05-17T01:35:00+00:00 2.0`.
  - `device-register`: no datapoints returned.
  - `topic-notifier`: no datapoints returned.
- Result: the required "zero invocations for >= 7 days before this PR is opened" gate fails for `search` and `live-status`.
- No build/test commands were run in this pass because no new source implementation changes were made and the pre-PR CloudWatch gate blocks implementation/PR handoff.

## Tradeoffs
- I did not open a PR, push, or make source changes because the CloudWatch prerequisite is explicitly required before the PR is opened.
- I did not revert or rewrite the existing ahead commit because it may contain work from another interrupted agent/session, and current instructions forbid reverting changes I did not make.
- The AWS-side deletes remain a human-gated follow-up after code and infrastructure changes are ready and reviewed.

## Blockers / follow-ups
- Blocked: wait until CloudWatch shows zero invocations for all four target functions (`search`, `live-status`, `device-register`, `topic-notifier`) across a full 7-day window.
- Reconcile the existing broad ahead commit before PR creation. If it is not the intended EPAC-1921 implementation, split or reset it with explicit owner approval rather than silently carrying unrelated changes into this ticket's PR.
- When the CloudWatch gate passes, implement the scoped Lambda removal, update OpenAPI and infrastructure, run backend verification, then rebase/push/open exactly one PR with label `autonomous` and `Reviewer-Boundary: review-only` in the PR body.

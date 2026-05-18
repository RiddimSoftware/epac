## Implementation notes
- EPAC-1921 was re-checked in Linear and remains active: status `In Progress`, status type `started`, `archivedAt: null`, `completedAt: null`, `canceledAt: null`.
- No source implementation changes were made in this pass because the issue's explicit pre-PR CloudWatch acceptance gate still fails.
- Current worktree: `/Users/sunny/code/epac/.symphony/workspaces/EPAC-1921`.
- Current branch: `symphony/epac-1921-backend-delete-unused-lambdas-search-live-status`.
- Target repository verified from origin remote: `git@github.com:RiddimSoftware/epac.git`.
- Prior repository inspection found the deletion is broader than four directories: `backend/go.work`, `backend/openapi/openapi.json`, Terraform/API Gateway/IAM/log group configuration, CI workflows, backend smoke checks, and OpenAPI tests reference at least some of these lambdas.
- Prior inspection also found `backend/live-status` serves `/calendar/house.ics` and `/api/v1/calendar/house.ics`; production Terraform routes named `house_calendar` and `house_calendar_legacy` currently point at `live-status`, so those routes need an explicit removal or migration decision when the gate passes.

## Verification evidence
- Linear fetch for `issue:EPAC-1921` on 2026-05-18 confirmed the issue remains active: `status: In Progress`, `statusType: started`, not archived/completed/canceled, estimate `8`.
- CloudWatch invocation gate checked `AWS/Lambda` `Invocations` in `us-east-1` over the required seven-day window: `2026-05-11T08:13:51Z` to `2026-05-18T08:13:51Z`.
- Command used:

```bash
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
start=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
for fn in search live-status device-register topic-notifier; do
  AWS_PROFILE=riddim-agent aws cloudwatch get-metric-statistics \
    --region us-east-1 \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value="$fn" \
    --start-time "$start" \
    --end-time "$now" \
    --period 86400 \
    --statistics Sum \
    --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' \
    --output text
done
```

- Results:
  - `search`: `2026-05-13T08:13:00+00:00 7.0`, `2026-05-14T08:13:00+00:00 5.0`.
  - `live-status`: `2026-05-14T08:13:00+00:00 13.0`, `2026-05-16T08:13:00+00:00 2.0`.
  - `device-register`: no datapoints returned in this seven-day window.
  - `topic-notifier`: no datapoints returned in this seven-day window.
- Because `search` and `live-status` both have invocations inside the last seven days, the acceptance criterion "Verify in CloudWatch ... zero invocations for >= 7 days before this PR is opened" is not satisfied.
- No build/test commands were run because no source files were changed.

## Tradeoffs
- I did not delete Lambda code, edit OpenAPI/Terraform, commit, push, or open a PR. Doing so would violate the issue's explicit seven-day zero-invocation precondition.
- The earliest likely passing time is after the latest observed `live-status` invocation ages out of the seven-day window, around 2026-05-23T08:13Z, assuming no additional invocations occur.

## Blockers / follow-ups
- Blocked: wait until CloudWatch shows zero invocations for all four functions (`search`, `live-status`, `device-register`, `topic-notifier`) across a full seven-day window.
- When the gate passes, implement the deletion across lambda directories, `backend/go.work`, OpenAPI, Terraform/API Gateway/IAM/log groups/EventBridge schedule references, CI workflows, smoke checks, and tests.
- After implementation, run backend verification including `cd backend && go build ./...` plus affected tests/format/validation, then commit, rebase on `origin/main`, push, and open exactly one PR with `gh pr create --label autonomous` and `Reviewer-Boundary: review-only` in the body.

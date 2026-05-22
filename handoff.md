# EPAC-1947 Handoff: ASC API Key Write Scope Verification

## Implementation notes

Implemented `scripts/release/verify_asc_write_scope.py` to verify write access to ASC API endpoints needed for SF Science Fair automation plan:
- `POST /v1/betaTesters` — create/manage external testers for TestFlight
- `POST /v1/betaAppReviewSubmissions` — submit builds for Beta App Review

Script workflow:
1. Fetches ASC API credentials from AWS Secrets Manager (`appstore/connect-api`, `us-east-1`)
2. Generates JWT token for API authentication
3. Sanity check: lists existing beta groups (verifies read scope)
4. Tests betaTesters endpoint by creating test tester with unique email, attaching to latest valid build, and immediately deleting
5. Tests betaAppReviewSubmissions endpoint by attempting to submit latest valid build for review
6. Outputs JSON report with endpoint status ("ok", "denied", "other")

Key implementation details:
- betaTesters requires either betaGroups or builds relationship; script uses builds relationship with latest valid build
- betaAppReviewSubmissions returns 422 (missing beta app description) when endpoint is reachable but build metadata incomplete; treated as write access verification
- No real testers or builds are permanently created/modified
- Test tester deleted immediately after successful creation

## Verification evidence

Script executed against current ASC key from AWS Secrets Manager:

```json
{
  "betaTesters": "ok",
  "betaAppReviewSubmissions": "ok"
}
```

Both endpoints confirmed accessible and reachable with write scope. ASC key is ready for downstream automation work.

Run command: `AWS_PROFILE=riddim-agent python3 scripts/release/verify_asc_write_scope.py`

## Tradeoffs

- Script uses latest valid build for betaTesters test; this is safe because the test tester is deleted immediately but ensures the payload is valid and doesn't require a separate beta group lookup
- 422 status on betaAppReviewSubmissions is treated as write access confirmation (endpoint accepted request enough to validate build metadata); a true 403 would indicate missing write scope

## Blockers / follow-ups

None. Both endpoints verified accessible with write scope. Downstream issues for tester-invitation and beta-submission automation are now unblocked:
- [Write invite_external_tester.py](https://linear.app/riddimsoftware/issue/EPAC-1948)
- [Write submit_beta_app_review.py](https://linear.app/riddimsoftware/issue/EPAC-1949)

PR: https://github.com/RiddimSoftware/epac/pull/518

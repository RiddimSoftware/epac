# Staging Environment

**Date:** 2026-04-28
**Status:** Accepted
**Ticket:** EPAC-156

## Decision

Split backend deployment into staging and production environments:

- Staging backend base URL: `https://staging-api.epac.riddimsoftware.com`
- Production backend base URL: `https://smun5g2szc.execute-api.us-east-1.amazonaws.com/production`

The iOS app reads `BackendBaseURL` from `Info.plist`, where Xcode expands `BACKEND_BASE_URL` from configuration files:

- `ios/Config/Debug.xcconfig` -> staging
- `ios/Config/Release.xcconfig` -> production

Fastlane can override `BACKEND_BASE_URL` through `xcargs`. The `Create Release` workflow sets that override to the staging URL so TestFlight candidates exercise staging before release, while local Release/App Store builds keep the production default unless explicitly overridden.

## Backend Deploy Process

Staging deploys are automatic on merge to `main` when `backend/**` changes:

```text
.github/workflows/deploy-staging.yml
```

The staging workflow expects:

- `AWS_BACKEND_STAGING_ROLE_ARN`
- Lambda names in the form `epac-<service>-staging`
- A separate staging database exposed to Lambda through each function's `DATABASE_URL`

Production deploys are manual:

```text
.github/workflows/deploy-production.yml
```

The production workflow expects:

- `AWS_BACKEND_PRODUCTION_ROLE_ARN`
- Lambda names in the form `epac-<service>-production`
- Production `DATABASE_URL` configured on production Lambda functions

## Verification

Before marking a staging deploy healthy:

1. Confirm `/health` returns `200` from the staging API.
2. Confirm `member-speeches` and other database-backed functions are using the staging database connection string.
3. Build a TestFlight candidate with `BACKEND_BASE_URL` set to the staging URL and verify staging Lambda logs show traffic from that build.

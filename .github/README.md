# GitHub Configuration

This directory contains GitHub Actions, issue templates, pull request templates,
and GitHub-specific contributor guidance for
[RiddimSoftware/epac](https://github.com/RiddimSoftware/epac).

For the project overview, App Store link, and local development commands, read
the repository [README](../README.md).

## Artifact Manifest Refresh

The `Refresh Artifact Manifest` workflow
(`.github/workflows/publish-artifacts.yml`) expects:

- `ARTIFACTS_BUCKET` repository variable.
- `ARTIFACTS_DISTRIBUTION_ID` repository variable.
- `AWS_ARTIFACTS_PUBLISHER_ROLE_ARN` repository or organization secret.

GitHub Actions assumes that role through OIDC, regenerates `manifest.json` from
existing S3 objects, and invalidates `/manifest.json` in CloudFront.

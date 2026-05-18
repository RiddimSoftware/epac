# GitHub Actions configuration

## Artifact manifest refresh

The `Refresh Artifact Manifest` workflow (`.github/workflows/publish-artifacts.yml`) requires these repository-level Actions variables:

- `ARTIFACTS_BUCKET`: S3 bucket name that stores published artifact files and `manifest.json`.
- `ARTIFACTS_DISTRIBUTION_ID`: CloudFront distribution ID for the artifact edge cache. The workflow invalidates `/manifest.json` after each refresh.

The workflow also expects `AWS_ARTIFACTS_PUBLISHER_ROLE_ARN` as a repository or organization Actions secret. GitHub Actions assumes this role through OIDC before regenerating `manifest.json` from the existing S3 objects and invalidating CloudFront.

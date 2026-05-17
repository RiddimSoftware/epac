# GitHub Actions configuration

## Artifact publishing

The `Publish Artifacts` workflow (`.github/workflows/publish-artifacts.yml`) requires these repository-level Actions variables:

- `ARTIFACTS_BUCKET`: S3 bucket name that receives generated artifact files and `manifest.json`.
- `ARTIFACTS_DISTRIBUTION_ID`: CloudFront distribution ID for the artifact edge cache. The workflow invalidates `/manifest.json` after each publish.

The workflow also expects `AWS_ARTIFACTS_PUBLISHER_ROLE_ARN` as a repository or organization Actions secret. GitHub Actions assumes this role through OIDC before syncing artifacts to S3 and invalidating CloudFront.

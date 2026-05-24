# epac terraform bootstrap

This module manages the core infrastructure required for Terraform remote state:
- S3 bucket for state storage with versioning and encryption
- DynamoDB table for state locking
- S3 + CloudFront + OAC artifact hosting in [`artifacts/`](./artifacts/)

## Usage

This module uses **remote state** (S3).

```bash
cd infra/terraform/core
export AWS_PROFILE=riddim-agent
terraform init
terraform plan
terraform apply
```

Once applied, other modules (staging, production) can use the created resources in their `backend "s3"` blocks.

The artifact module defaults to `epac-assets.riddimsoftware.com` because `epac.app` is not currently present as a public Route 53 hosted zone. See [`artifacts/README.md`](./artifacts/README.md) for switching to `assets.epac.app` after that zone exists and for the post-apply smoke test.

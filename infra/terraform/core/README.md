# epac core infrastructure

This module manages shared epac infrastructure:

- S3 + CloudFront + OAC artifact hosting in [`artifacts/`](./artifacts/)

Terraform remote state storage is created by [`../bootstrap.sh`](../bootstrap.sh), not by this module. That avoids the bootstrap cycle where Terraform needs a remote backend before it can create its own state bucket.

## Usage

This module uses S3 remote state with DynamoDB locking.

```bash
cd infra/terraform
./bootstrap.sh staging
cd core
export AWS_PROFILE=riddim-agent
terraform init
terraform plan
terraform apply
```

The artifact module defaults to `epac-assets.riddimsoftware.com` because `epac.app` is not currently present as a public Route 53 hosted zone. See [`artifacts/README.md`](./artifacts/README.md) for switching to `assets.epac.app` after that zone exists and for the post-apply smoke test.

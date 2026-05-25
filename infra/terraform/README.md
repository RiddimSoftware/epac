# epac infrastructure

Terraform modules for the epac project:

- **[core/](./core/)**: Core infrastructure for shared artifact hosting (S3, CloudFront, OAC, ACM, Route53).
- **[staging/](./staging/)**: Staging environment resources (Lambda, API Gateway, Route53).
- **[production/](./production/)**: Production environment resources (Lambda, API Gateway, Route53).

## Remote State

All modules use an S3 backend with DynamoDB locking in `us-east-1`.

| Workspace | State bucket | State key | Lock table |
|---|---|---|---|
| core | `epac-tfstate-core-227530433709` | `core.tfstate` | `epac-tfstate-lock-core` |
| staging | `epac-tfstate-staging-227530433709` | `staging.tfstate` | `epac-tfstate-lock-staging` |
| production | `epac-tfstate-production-227530433709` | `production.tfstate` | `epac-tfstate-lock-production` |

`infra/terraform/bootstrap.sh` (added in A1) handles the per-account bootstrap for state storage.
Backend blocks are declared in each workspace `versions.tf` and were set by A2.

The account ID is hard-coded in each backend block because Terraform loads backend configuration before variables are available.

## Local operator path

From a terminal:

```bash
aws sso login
bash infra/terraform/bootstrap.sh <env>
cd infra/terraform/<env>
terraform init
terraform plan
```

`<env>` is one of `core`, `staging`, or `production`.

For an existing repository, this is the standard local path after bootstrap.

### Fresh AWS account

From a fresh account, this is the full path:

1. `aws sso login`
2. `bash infra/terraform/bootstrap.sh <env>`
3. `cd infra/terraform/<env> && terraform init && terraform plan`

`bootstrap.sh` owns the substrate creation step, including any first-time state migration; no additional human AWS steps are required.

## Existing committed local state

Committed local `terraform.tfstate*` files were removed after the migration in [EPAC-2060](https://github.com/RiddimSoftware/epac/pull/594).

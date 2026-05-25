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

The account ID is hard-coded in each backend block because Terraform loads backend configuration before variables are available.

## Bootstrap

Run the bootstrap script before `terraform init` in a fresh account or before migrating existing state:

```bash
cd infra/terraform
export AWS_PROFILE=riddim-agent
./bootstrap.sh staging
```

`bootstrap.sh staging` creates the `core` and `staging` backend resources. `bootstrap.sh production` creates the `core` and `production` backend resources. The script is idempotent; existing buckets and lock tables produce `bucket exists, no-op` and `lock table exists, no-op` log lines.

No human AWS console or pre-created bucket/table steps are required for state storage.

## Local Terraform Use

```bash
cd infra/terraform/staging
export AWS_PROFILE=riddim-agent
terraform init
terraform plan
```

For the shared artifact infrastructure, use `infra/terraform/core`. For production, use `infra/terraform/production` and keep the existing production human gate before any apply.

To migrate an already-initialized local checkout from the previous backend configuration to the current backend:

```bash
terraform init -migrate-state -force-copy
terraform state list
terraform plan
```

Do not commit generated state, plan, variable, lock, or `.terraform/` files.

## Bootstrap Smoke Test

From a scratch AWS account or disposable sub-account with the IAM permissions documented in `bootstrap.sh`, run:

```bash
cd infra/terraform
./bootstrap.sh staging
./bootstrap.sh staging
aws s3api get-bucket-versioning --bucket "epac-tfstate-staging-$(aws sts get-caller-identity --query Account --output text --region us-east-1)" --region us-east-1
aws dynamodb describe-table --table-name epac-tfstate-lock-staging --region us-east-1 --query 'Table.BillingModeSummary.BillingMode'
```

The first run creates the `core` and `staging` buckets/tables. The second run exits 0 with no-op lines for both workspaces.

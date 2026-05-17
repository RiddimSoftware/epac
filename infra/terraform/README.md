# epac infrastructure

Terraform modules for the epac project:

- **[core/](./core/)**: Core infrastructure for Terraform remote state plus artifact hosting (S3, CloudFront, OAC, ACM, Route53).
- **[staging/](./staging/)**: Staging environment resources (Lambda, API Gateway, Route53).
- **[production/](./production/)**: Production environment resources (Lambda, API Gateway, Route53).

## Remote State

All modules use the remote S3 backend with DynamoDB locking.

1. **Bootstrap**: The `core` module has been applied and its state is stored in S3.
2. **Migration**: Once the core resources exist, run `terraform init` in `staging` and `production` to migrate existing local state to the remote backend.

# epac terraform bootstrap

This module manages the core infrastructure required for Terraform remote state:
- S3 bucket for state storage with versioning and encryption
- DynamoDB table for state locking

## Usage

This module uses **remote state** (S3).

```bash
cd infra/terraform/core
export AWS_PROFILE=riddim-agent
terraform init
terraform apply
```

Once applied, other modules (staging, production) can use the created resources in their `backend "s3"` blocks.

# epac staging infrastructure

Terraform module for the epac staging backend: 10 Lambda functions, API Gateway v2 custom domain, ACM certificate, and Route53 DNS records.

## Prerequisites

- Terraform >= 1.5
- AWS credentials with access to the `riddim-agent` profile
- All resources already exist in AWS — run `terraform import` (see below) before `terraform apply`

## Usage

```bash
cd infra/terraform/staging
export AWS_PROFILE=riddim-agent
terraform init
terraform plan   # should show 0 changes after import
terraform apply  # idempotent once imported
```

## Import existing resources

All staging resources were created manually (EPAC-1847/1848/1849). Import them into state before running `apply`:

```bash
export AWS_PROFILE=riddim-agent

# Lambda functions
terraform import 'aws_lambda_function.staging["daily-fetch"]'     epac-daily-fetch-staging
terraform import 'aws_lambda_function.staging["loader"]'          epac-loader-staging
terraform import 'aws_lambda_function.staging["search"]'          epac-search-staging
terraform import 'aws_lambda_function.staging["member-speeches"]' epac-member-speeches-staging
terraform import 'aws_lambda_function.staging["on-this-day"]'     epac-on-this-day-staging
terraform import 'aws_lambda_function.staging["riding-boundary"]' epac-riding-boundary-staging
terraform import 'aws_lambda_function.staging["health"]'          epac-health-staging
terraform import 'aws_lambda_function.staging["device-register"]' epac-device-register-staging
terraform import 'aws_lambda_function.staging["openapi"]'         epac-openapi-staging
terraform import 'aws_lambda_function.staging["live-status"]'     epac-live-status-staging

# ACM certificate (aws_acm_certificate_validation does not support import; cert is already issued)
terraform import aws_acm_certificate.staging_api \
  arn:aws:acm:us-east-1:227530433709:certificate/4383b7e3-7064-45ed-b009-0f3d14d80540

# Route53 ACM validation CNAME
terraform import \
  'aws_route53_record.acm_validation["staging-api.epac.riddimsoftware.com"]' \
  Z0066450A0OUY8MCI6XV__a9d0b8dee4d369c091e53099fff1bed3.staging-api.epac.riddimsoftware.com._CNAME

# API Gateway custom domain
terraform import aws_apigatewayv2_domain_name.staging staging-api.epac.riddimsoftware.com

# API Gateway API mapping (format: api-mapping-id/domain-name)
# oo5a6a maps staging-api.epac.riddimsoftware.com → epac-api-staging (f4x35gduxl)
terraform import aws_apigatewayv2_api_mapping.staging \
  oo5a6a/staging-api.epac.riddimsoftware.com

# Route53 alias A record
terraform import aws_route53_record.staging_api \
  Z0066450A0OUY8MCI6XV_staging-api.epac.riddimsoftware.com_A
```

## Notes

- Lambda **code** is managed by `.github/workflows/backend-staging.yml`, not Terraform. The `placeholder.zip` is used only when creating a function from scratch; `lifecycle.ignore_changes` prevents Terraform from overwriting CI-deployed code.
- State is local (`terraform.tfstate`). Add `.gitignore` entries for `*.tfstate*` and `.terraform/` — these are already covered by the repo root `.gitignore`.
- Remote state (S3 + DynamoDB lock) is out of scope for now; tracked as a follow-on issue.

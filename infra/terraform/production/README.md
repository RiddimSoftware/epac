# epac production infrastructure

Terraform module for the epac production backend: the production HTTP API, production stage, 10 bare-name Lambda functions, API Gateway v2 routes, Lambda invoke permissions, custom domain, ACM certificate, and Route53 DNS records.

## Prerequisites

- Terraform >= 1.5
- AWS credentials with access to the `riddim-agent` profile
- Explicit human sign-off before any production `terraform apply`
- Existing resources imported before planning against production

## Usage

```bash
cd infra/terraform/production
export AWS_PROFILE=riddim-agent
terraform init
terraform plan
```

Do not run `terraform apply` without the external validation gate in EPAC-1851. Production is live.

## Import existing resources

Import resources that already exist in AWS before the first production plan:

```bash
export AWS_PROFILE=riddim-agent

# HTTP API and production stage
terraform import aws_apigatewayv2_api.production smun5g2szc
terraform import aws_apigatewayv2_stage.production smun5g2szc/production

# Existing production Lambda functions
terraform import 'aws_lambda_function.production["search"]' search
terraform import 'aws_lambda_function.production["member-speeches"]' member-speeches
terraform import 'aws_lambda_function.production["daily-fetch"]' daily-fetch

# Existing production Lambda invoke permissions
terraform import 'aws_lambda_permission.production_apigw["search"]' search/apigateway-search
terraform import 'aws_lambda_permission.production_apigw["member-speeches"]' member-speeches/epac-api-gateway

# ACM certificate (aws_acm_certificate_validation does not support import; cert is already issued)
terraform import aws_acm_certificate.production_api \
  arn:aws:acm:us-east-1:227530433709:certificate/002670fa-5e3a-4187-8fe5-679b8cbb0bef

# Route53 ACM validation CNAME
terraform import aws_route53_record.acm_validation \
  Z0066450A0OUY8MCI6XV__829ab5a6bd19a6588d86c3f682836534.api.epac.riddimsoftware.com._CNAME

# API Gateway custom domain
terraform import aws_apigatewayv2_domain_name.production api.epac.riddimsoftware.com

# API Gateway API mapping (format: api-mapping-id/domain-name)
# wvkpli maps api.epac.riddimsoftware.com -> epac-api-api (smun5g2szc) production stage.
terraform import aws_apigatewayv2_api_mapping.production \
  wvkpli/api.epac.riddimsoftware.com

# Route53 alias A record
terraform import aws_route53_record.production_api \
  Z0066450A0OUY8MCI6XV_api.epac.riddimsoftware.com_A

# Existing API Gateway integrations that already target bare production Lambdas
terraform import 'aws_apigatewayv2_integration.production["search"]' smun5g2szc/1h3ggkc
terraform import 'aws_apigatewayv2_integration.production["member-speeches"]' smun5g2szc/1qd8e9q

# Existing API Gateway routes
terraform import aws_apigatewayv2_route.search_legacy smun5g2szc/kia4ymj
terraform import aws_apigatewayv2_route.search_speeches smun5g2szc/ozqup4u
terraform import aws_apigatewayv2_route.member_speeches_legacy smun5g2szc/qxcszqb
terraform import aws_apigatewayv2_route.member_speeches smun5g2szc/2wpw8mm
terraform import aws_apigatewayv2_route.health smun5g2szc/cto5jer
terraform import aws_apigatewayv2_route.on_this_day smun5g2szc/ogjkher
terraform import aws_apigatewayv2_route.riding_boundary smun5g2szc/cqw6o3i
terraform import aws_apigatewayv2_route.live_status smun5g2szc/f7lnnps
terraform import aws_apigatewayv2_route.device_register smun5g2szc/lorqdum
```

## First apply expectations

Only `search`, `member-speeches`, and `daily-fetch` exist as bare-name production Lambda functions today. The other seven functions are intentionally declared from `placeholder.zip`; their code and environment are deployment-workflow concerns.

Some currently existing production API routes still target staging Lambda functions. This module rewires those routes to bare-name production Lambda functions. After the missing production functions are created and all existing resources above are imported, a human should run `terraform plan` and confirm the remaining changes are the expected production cutover only. A later no-op plan should show 0 changes.

## Notes

- Lambda code is not managed by Terraform. `placeholder.zip` is used only to create missing production functions; `lifecycle.ignore_changes` prevents Terraform from overwriting deployed code.
- Production stage `auto_deploy` remains `false` to preserve the existing production release gate.
- State is local (`terraform.tfstate`). Remote state is out of scope here and tracked separately in EPAC-1852.

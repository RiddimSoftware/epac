# epac production infrastructure

Terraform module for the epac production backend: the production HTTP API, production stage, 13 bare-name Lambda functions, API Gateway v2 routes, Lambda invoke permissions, custom domain, ACM certificate, and Route53 DNS records.

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
terraform import 'aws_lambda_function.production["loader"]' loader
terraform import 'aws_lambda_function.production["members"]' members
terraform import 'aws_lambda_function.production["sittings"]' sittings
terraform import 'aws_lambda_function.production["bills"]' bills
terraform import 'aws_lambda_function.production["on-this-day"]' on-this-day
terraform import 'aws_lambda_function.production["riding-boundary"]' riding-boundary
terraform import 'aws_lambda_function.production["health"]' health
terraform import 'aws_lambda_function.production["device-register"]' device-register
terraform import 'aws_lambda_function.production["openapi"]' openapi
terraform import 'aws_lambda_function.production["live-status"]' live-status
```

The EPAC-1914 artifact-backed functions (`members`, `sittings`, and `bills`) may be new in an account. If the `terraform import` command reports that one of them does not exist, omit that import and let Terraform create it from `placeholder.zip`; the backend deployment workflow updates the code and artifact environment afterward.

```bash

# Production API Gateway Lambda invoke permissions
#
# Do not import the older search/apigateway-search or
# member-speeches/epac-api-gateway statements as these resources. Those live
# statements are narrow compatibility permissions, and existing apigw-production-*
# statements belong to an older API. Terraform creates distinct non-conflicting
# apigw-epac-api-* statements for this production API.

# ACM certificate (aws_acm_certificate_validation does not support import; cert is already issued)
terraform import aws_acm_certificate.production_api \
  arn:aws:acm:us-east-1:227530433709:certificate/f921ddcd-6d4d-4377-8b4e-00cea46d92a6

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
terraform import 'aws_apigatewayv2_integration.production["riding-boundary"]' smun5g2szc/3c889eq
terraform import 'aws_apigatewayv2_integration.production["openapi"]' smun5g2szc/9jxvyi8
terraform import 'aws_apigatewayv2_integration.production["health"]' smun5g2szc/bao37dr
terraform import 'aws_apigatewayv2_integration.production["live-status"]' smun5g2szc/bkgkrrb
terraform import 'aws_apigatewayv2_integration.production["device-register"]' smun5g2szc/ngmy84j
terraform import 'aws_apigatewayv2_integration.production["on-this-day"]' smun5g2szc/vqfubhe

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
terraform import aws_apigatewayv2_route.device_register_legacy smun5g2szc/l4f7i6t
terraform import aws_apigatewayv2_route.house_calendar smun5g2szc/dcan8nq
terraform import aws_apigatewayv2_route.house_calendar_legacy smun5g2szc/q86b4uc
terraform import aws_apigatewayv2_route.openapi_json smun5g2szc/exikf69
terraform import aws_apigatewayv2_route.openapi_docs smun5g2szc/iv982t1
terraform import aws_apigatewayv2_route.openapi_json_v1 smun5g2szc/o9ecr6c
terraform import aws_apigatewayv2_route.openapi_docs_v1 smun5g2szc/oolp6lm
```

## First apply expectations

All 13 bare-name production Lambda functions currently exist and should be imported. If a function is absent in a fresh account, Terraform will create it from `placeholder.zip`; code and environment remain deployment-workflow concerns.

The production API also contains older staging-target integrations left over from the API split. No current route should target those integrations. They are intentionally not imported into this desired-state module; after the managed resources above are imported, a human should run `terraform plan` and confirm the remaining changes are limited to creating the new `apigw-epac-api-*` Lambda invoke permissions. A later no-op plan should show 0 changes.

## Notes

- Lambda code is not managed by Terraform. `placeholder.zip` is used only to create missing production functions; `lifecycle.ignore_changes` prevents Terraform from overwriting deployed code.
- Production stage `auto_deploy` remains `false` to preserve the existing production release gate.
- State is remote (S3). Remote state (S3 + DynamoDB lock) was added in EPAC-1852. State is stored in the `epac-terraform-state` bucket with locks in `epac-terraform-locks`.

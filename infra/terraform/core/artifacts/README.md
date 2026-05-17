# epac artifacts module

This module provisions the public read surface for migrated epac artifacts:

- S3 bucket with versioning, public access blocked, bucket-owner-enforced object ownership, AES-256 server-side encryption, GET/HEAD CORS, and non-current version expiry after 90 days.
- CloudFront distribution using Origin Access Control (OAC), not legacy OAI.
- CloudFront uses AWS managed `Managed-CachingOptimized` and `Managed-CORS-S3Origin`. AWS exposes `Managed-CORS-S3Origin` as an origin request policy, so the distribution pairs it with the managed `Managed-CORS-With-Preflight` response headers policy for browser-visible CORS headers.
- ACM certificate and DNS validation records for the custom domain.
- Route 53 alias records for the custom domain.
- Bucket policy allowing `s3:GetObject` only from the CloudFront distribution service principal, scoped by `AWS:SourceArn`.

## Chosen custom domain

This module defaults to `epac-assets.riddimsoftware.com` in the `riddimsoftware.com` hosted zone.

`assets.epac.app` remains the preferred final domain, but a read-only Route 53 check on 2026-05-17 did not find an `epac.app` hosted zone. To switch after the apex zone exists, set:

```hcl
artifacts_custom_domain_name = "assets.epac.app"
artifacts_route53_zone_name  = "epac.app"
```

## Usage

From the core stack:

```bash
cd infra/terraform/core
export AWS_PROFILE=riddim-agent
terraform init
terraform plan
terraform apply
```

After apply, upload the smoke-test file and wait until the CloudFront distribution status is `Deployed`:

```bash
printf "ok\n" > /tmp/epac-healthz.txt
aws s3 cp /tmp/epac-healthz.txt "s3://$(terraform output -raw artifacts_bucket_name)/healthz.txt" --content-type text/plain
curl -I "https://$(terraform output -raw artifacts_custom_domain_name)/healthz.txt"
```

The smoke test passes when `curl` returns `HTTP 200` with a `via: ...cloudfront...` header.

## Outputs

- `bucket_arn`
- `bucket_name`
- `distribution_id`
- `distribution_domain_name`
- `custom_domain_name`

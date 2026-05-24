locals {
  origin_id = "epac-artifacts-s3-origin"

  tags = merge(
    {
      Project   = "epac"
      ManagedBy = "Terraform"
      Ticket    = "EPAC-1906"
    },
    var.tags
  )
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "cors_s3_origin" {
  name = "Managed-CORS-S3Origin"
}

data "aws_cloudfront_response_headers_policy" "cors_with_preflight" {
  name = "Managed-CORS-With-Preflight"
}

data "aws_route53_zone" "artifacts" {
  name         = trimsuffix(var.route53_zone_name, ".")
  private_zone = false
}

resource "aws_s3_bucket" "artifacts" {
  bucket = var.bucket_name

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.artifacts]
}

resource "aws_s3_bucket_cors_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_acm_certificate" "artifacts" {
  domain_name       = var.custom_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.artifacts.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 300
  type            = each.value.type
  zone_id         = data.aws_route53_zone.artifacts.zone_id
}

resource "aws_acm_certificate_validation" "artifacts" {
  certificate_arn         = aws_acm_certificate.artifacts.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_cloudfront_origin_access_control" "artifacts" {
  name                              = "epac-artifacts-oac"
  description                       = "CloudFront OAC for epac artifact reads"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "artifacts" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  aliases         = [var.custom_domain_name]
  comment         = "epac artifact hosting"

  origin {
    domain_name              = aws_s3_bucket.artifacts.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.artifacts.id
    origin_id                = local.origin_id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress                   = true
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.cors_s3_origin.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.cors_with_preflight.id
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.artifacts.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = local.tags
}

data "aws_iam_policy_document" "artifacts_read" {
  statement {
    sid     = "AllowCloudFrontReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.artifacts.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.artifacts.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifacts_read.json
}

resource "aws_route53_record" "artifacts_ipv4" {
  name    = var.custom_domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.artifacts.zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.artifacts.domain_name
    zone_id                = aws_cloudfront_distribution.artifacts.hosted_zone_id
  }
}

resource "aws_route53_record" "artifacts_ipv6" {
  name    = var.custom_domain_name
  type    = "AAAA"
  zone_id = data.aws_route53_zone.artifacts.zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.artifacts.domain_name
    zone_id                = aws_cloudfront_distribution.artifacts.hosted_zone_id
  }
}

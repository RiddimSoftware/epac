module "artifacts" {
  source = "./artifacts"

  providers = {
    aws = aws.us_east_1
  }

  bucket_name        = var.artifacts_bucket_name
  custom_domain_name = var.artifacts_custom_domain_name
  route53_zone_name  = var.artifacts_route53_zone_name
}

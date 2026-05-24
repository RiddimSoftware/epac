resource "aws_s3_bucket" "terraform_state" {
  bucket = "epac-terraform-state"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project   = "epac"
    ManagedBy = "terraform"
    Ticket    = "EPAC-1852"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "epac-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = "epac"
    ManagedBy = "terraform"
    Ticket    = "EPAC-1852"
  }
}

module "artifacts" {
  source = "./artifacts"

  providers = {
    aws = aws.us_east_1
  }

  bucket_name        = var.artifacts_bucket_name
  custom_domain_name = var.artifacts_custom_domain_name
  route53_zone_name  = var.artifacts_route53_zone_name
}

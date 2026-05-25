terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "epac-tfstate-production-227530433709"
    key            = "production.tfstate"
    region         = "us-east-1"
    dynamodb_table = "epac-tfstate-lock-production"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

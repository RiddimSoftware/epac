terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "epac-tfstate-core-227530433709"
    key            = "core.tfstate"
    region         = "us-east-1"
    dynamodb_table = "epac-tfstate-lock-core"
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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

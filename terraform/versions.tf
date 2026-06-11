terraform {
  # use_lockfile (native S3 state locking, no DynamoDB) requires Terraform >= 1.10.
  required_version = ">= 1.10.0"

  # Remote state in S3 (same account). Bucket/key/region are supplied at
  # `terraform init` time via -backend-config, since a backend block can't read
  # variables. The bucket is created out-of-band by the workflows (it can't be
  # managed by the very state it stores).
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

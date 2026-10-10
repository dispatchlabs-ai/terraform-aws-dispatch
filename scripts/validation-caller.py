#!/usr/bin/env python3
"""Generate a source-only validation caller with the required edge provider alias.

Terraform cannot validate a child module's configuration_aliases as an isolated
root. This ignored caller supplies both providers; no credentials or apply.
"""
from pathlib import Path

root = Path('.local/validation')
root.mkdir(parents=True, exist_ok=True)
(root / 'main.tf').write_text('''terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.67.0" }
  }
}
provider "aws" { region = "us-east-1" }
provider "aws" {
  alias = "edge"
  region = "us-east-1"
}
module "dispatch" {
  source = "../.."
  providers = { aws = aws, aws.edge = aws.edge }
  name = "dispatch-validation"
  vpc_cidr = "10.80.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
}
''')

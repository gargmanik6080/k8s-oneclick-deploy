# Only use AZs in the region that actually offer the chosen instance type.
# m3.medium is a previous-gen type missing from some AZs (e.g. us-east-1e); this avoids
# node-group create failures.
data "aws_ec2_instance_type_offerings" "azs" {
  filter {
    name   = "instance-type"
    values = var.instance_types
  }
  location_type = "availability-zone"
}

locals {
  azs = slice(sort(distinct(data.aws_ec2_instance_type_offerings.azs.locations)), 0, 2)

  tags = {
    Project   = "k8s-oneclick-deploy"
    ManagedBy = "terraform"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 101), cidrsubnet(var.vpc_cidr, 8, 102)]

  # Single NAT keeps cost/time down; nodes still get outbound internet to pull images.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags let the in-tree AWS cloud provider place LoadBalancer ELBs in the right subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # Public endpoint so the GitHub Actions runner can reach the API server.
  cluster_endpoint_public_access = true

  # Grants the Terraform/CI caller cluster-admin via an EKS access entry, so the same
  # AWS creds can run kubectl/helm immediately after apply.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = var.ami_type
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.instance_types
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size
    }
  }

  tags = local.tags
}

variable "region" {
  description = "AWS region (sandbox allows us-east-1, us-east-2, us-west-2)."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "oneclick-eks"
}

variable "kubernetes_version" {
  description = "EKS control plane / node Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "instance_types" {
  description = "Node instance types. Sandbox only allows tiny types; m3.medium has the most RAM (3.75 GiB)."
  type        = list(string)
  default     = ["m3.medium"]
}

variable "ami_type" {
  description = "EKS managed node group AMI type. Override to AL2_x86_64 only on older k8s versions if AL2023 rejects m3."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "desired_size" {
  description = "Desired node count (3 gives the trimmed monitoring stack room to schedule on 1-vCPU nodes)."
  type        = number
  default     = 3
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

output "region" {
  description = "AWS region the cluster runs in."
  value       = var.region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "configure_kubeconfig" {
  description = "Command to point kubectl/helm at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "node_azs" {
  description = "Availability zones selected for the node group."
  value       = local.azs
}

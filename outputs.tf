output "cluster_name" {
  description = "Cluster name for explicit kubeconfig setup."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API endpoint; reachable publicly only from the configured operator CIDRs."
  value       = aws_eks_cluster.this.endpoint
}

output "vpc_id" {
  description = "Dedicated VPC for platform controller configuration."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Installation VPC CIDR, for application ingress policy."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Explicit internet-facing load-balancer subnet IDs."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "load_balancer_controller_role_arn" {
  description = "IRSA role for the kube-system/aws-load-balancer-controller service account."
  value       = aws_iam_role.system["ingress"].arn
}

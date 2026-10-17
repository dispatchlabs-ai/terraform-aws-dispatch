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

output "distributed_postgres" {
  description = "Private database endpoint and operator-only credential reference; no secret values. Null when the distributed database is disabled."
  value = var.distributed_postgres == null ? null : {
    identifier           = aws_db_instance.distributed["workers"].identifier
    host                 = aws_db_instance.distributed["workers"].address
    port                 = aws_db_instance.distributed["workers"].port
    master_secret_arn    = aws_db_instance.distributed["workers"].master_user_secret[0].secret_arn
    security_group_id    = aws_security_group.distributed_database["workers"].id
    private_subnet_cidrs = [for subnet in aws_subnet.private : subnet.cidr_block]
  }
}

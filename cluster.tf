resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 7
  tags              = local.tags
}

resource "aws_eks_cluster" "this" {
  name                          = var.name
  role_arn                      = aws_iam_role.cluster.arn
  version                       = var.kubernetes_version
  bootstrap_self_managed_addons = false
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.private : subnet.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.api_access_cidrs
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster, aws_cloudwatch_log_group.cluster]
  tags       = local.tags
}

resource "aws_eks_access_entry" "admin" {
  for_each      = var.cluster_admin_arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
  tags          = local.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = var.cluster_admin_arns
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin[each.key].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_addon" "cni" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "vpc-cni"
  addon_version            = var.addon_versions.vpc_cni
  service_account_role_arn = aws_iam_role.system["cni"].arn
  # Cilium chains after aws-cni for IPAM and owns all policy enforcement. Never
  # run both policy agents; an existing cluster requires a stopped-owner migration.
  configuration_values = jsonencode({
    enableNetworkPolicy = var.network_policy_provider == "aws-vpc-cni" ? "true" : "false"
  })
  depends_on = [aws_iam_role_policy_attachment.system]
  tags       = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = var.addon_versions.kube_proxy
  tags          = local.tags
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${var.name}-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name}-node" })
  }
  tags = local.tags
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-system"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  instance_types  = [var.node_instance_type]

  # Cilium removes this bootstrap taint only after installing the chained CNI.
  # Newly added/replacement nodes must not run application Pods with AWS IPAM
  # alone while the separately installed policy agent is still starting.
  dynamic "taint" {
    for_each = var.network_policy_provider == "cilium" ? [true] : []
    content {
      key    = "node.cilium.io/agent-not-ready"
      value  = "true"
      effect = "NO_EXECUTE"
    }
  }

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count + 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes, aws_eks_addon.cni,
    aws_eks_addon.kube_proxy, aws_route.nat, aws_route_table_association.private,
  ]
  tags = local.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = var.addon_versions.coredns
  # Trusted foundation services must become healthy before the separate Cilium
  # installation. Application Pods never receive this bootstrap toleration.
  configuration_values = var.network_policy_provider == "cilium" ? jsonencode({
    tolerations = [
      { key = "CriticalAddonsOnly", operator = "Exists" },
      { key = "node-role.kubernetes.io/control-plane", operator = "Exists", effect = "NoSchedule" },
      { key = "node-role.kubernetes.io/master", operator = "Exists", effect = "NoSchedule" },
      { key = "node.cilium.io/agent-not-ready", operator = "Exists", effect = "NoExecute" },
    ]
  }) : null
  depends_on = [aws_eks_node_group.this]
  tags       = local.tags
}

resource "aws_eks_addon" "ebs" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.addon_versions.ebs_csi
  service_account_role_arn = aws_iam_role.system["ebs"].arn
  configuration_values = var.network_policy_provider == "cilium" ? jsonencode({
    controller = {
      tolerations = [
        { key = "CriticalAddonsOnly", operator = "Exists" },
        { key = "node.cilium.io/agent-not-ready", operator = "Exists", effect = "NoExecute" },
        { operator = "Exists", effect = "NoExecute", tolerationSeconds = 300 },
      ]
    }
  }) : null
  depends_on = [aws_eks_node_group.this, aws_iam_role_policy_attachment.system]
  tags       = local.tags
}

resource "aws_eks_addon" "pod_identity_agent" {
  count         = var.pod_identity_agent_version == null ? 0 : 1
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = var.pod_identity_agent_version

  # This foundation has IPv4 networking. The agent uses the existing node role's
  # AmazonEKSWorkerNodePolicy permission, not an IRSA service-account role.
  configuration_values = jsonencode({
    agent = { additionalArgs = { "-b" = "169.254.170.23" } }
  })

  depends_on = [aws_eks_node_group.this, aws_iam_role_policy_attachment.nodes]
  tags       = local.tags
}

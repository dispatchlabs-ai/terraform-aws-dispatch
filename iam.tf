data "aws_partition" "current" {}

resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "eks.amazonaws.com" }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "nodes" {
  name = "${var.name}-nodes"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each   = toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly"])
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# IAM retrieves the issuer thumbprint itself. Do not pin an intermediate TLS certificate.
resource "aws_iam_openid_connect_provider" "cluster" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  tags           = local.tags
}

resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${var.name}-load-balancer-controller"
  description = "Upstream AWS Load Balancer Controller v3.6.0 policy; see policies/README.md."
  policy      = file("${path.module}/policies/aws-load-balancer-controller-v3.6.0.json")
  tags        = local.tags
}

locals {
  system_identities = {
    cni = {
      service_account = "aws-node"
      policy_arn      = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
    }
    ebs = {
      service_account = "ebs-csi-controller-sa"
      policy_arn      = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
    ingress = {
      service_account = "aws-load-balancer-controller"
      policy_arn      = aws_iam_policy.load_balancer_controller.arn
    }
  }
  oidc_issuer = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
}

resource "aws_iam_role" "system" {
  for_each = local.system_identities
  name     = "${var.name}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:${each.value.service_account}"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "system" {
  for_each   = local.system_identities
  role       = aws_iam_role.system[each.key].name
  policy_arn = each.value.policy_arn
}

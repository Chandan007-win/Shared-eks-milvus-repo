data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = [for index, az in local.azs : cidrsubnet(var.vpc_cidr, 4, index)]
  public_subnets  = [for index, az in local.azs : cidrsubnet(var.vpc_cidr, 4, index + 8)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_support   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.18.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access = true
  enable_irsa            = true

  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    shared = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }

  tags = var.tags
}

resource "aws_s3_bucket" "milvus" {
  bucket = var.s3_bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "milvus" {
  bucket = aws_s3_bucket.milvus.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "milvus" {
  bucket = aws_s3_bucket.milvus.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "milvus_s3" {
  statement {
    sid    = "MilvusBucketList"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      aws_s3_bucket.milvus.arn
    ]
  }

  statement {
    sid    = "MilvusObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "${aws_s3_bucket.milvus.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "milvus_s3" {
  name   = "${var.cluster_name}-milvus-s3-policy"
  policy = data.aws_iam_policy_document.milvus_s3.json

  tags = var.tags
}

data "aws_iam_policy_document" "milvus_irsa_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values = [
        "system:serviceaccount:${var.milvus_namespace}:${var.milvus_service_account_name}"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "milvus_irsa" {
  name               = "${var.cluster_name}-milvus-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.milvus_irsa_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "milvus_s3" {
  role       = aws_iam_role.milvus_irsa.name
  policy_arn = aws_iam_policy.milvus_s3.arn
}

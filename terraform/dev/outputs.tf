output "aws_region" {
  value = var.aws_region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "s3_bucket_name" {
  value = aws_s3_bucket.milvus.bucket
}

output "milvus_irsa_role_arn" {
  value = aws_iam_role.milvus_irsa.arn
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

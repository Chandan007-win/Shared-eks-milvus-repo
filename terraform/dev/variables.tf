variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "ap-south-1"
}

variable "cluster_name" {
  type        = string
  default     = "shared-dev-eks"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version"
  default     = "1.33"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR range"
  default     = "10.20.0.0/16"
}

variable "node_instance_types" {
  type        = list(string)
  description = "EKS managed node group instance types"
  default     = ["t3.large"]
}

variable "node_desired_size" {
  type        = number
  description = "Desired number of worker nodes"
  default     = 2
}

variable "node_min_size" {
  type        = number
  description = "Minimum number of worker nodes"
  default     = 2
}

variable "node_max_size" {
  type        = number
  description = "Maximum number of worker nodes"
  default     = 3
}

variable "milvus_namespace" {
  type        = string
  description = "Kubernetes namespace for Milvus"
  default     = "milvus"
}

variable "milvus_service_account_name" {
  type        = string
  description = "Service account name for Milvus IRSA"
  default     = "milvus-s3-access-sa"
}

variable "s3_bucket_name" {
  type        = string
}

variable "tags" {
  type        = map(string)
  description = "Common resource tags"
  default = {
    Terraform   = "true"
    Project     = "milvus"
    Environment = "dev"
  }
}

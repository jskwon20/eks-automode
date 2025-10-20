output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "EKS 클러스터 이름"
}

output "eks_cluster_role_arn" {
  value       = module.eks.cluster_iam_role_arn
  description = "EKS 클러스터 IAM 역할 ARN"
}

output "hosted_zone_name_servers" {
  value = data.aws_route53_zone.this.name_servers
}

output "update_kubeconfig" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ap-northeast-2"
}
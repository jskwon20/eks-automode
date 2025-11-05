# 다른 사용자를 EKS 클러스터에 추가하는 예시
# 실제 사용 시 주석을 해제하고 사용자 정보를 수정하세요

# resource "aws_eks_access_entry" "additional_user" {
#   cluster_name      = module.eks.cluster_name
#   principal_arn     = "arn:aws:iam::637341921879:user/다른사용자이름"
#   kubernetes_groups = ["system:masters"]  # 또는 적절한 권한 그룹
#   type             = "STANDARD"
# }

# resource "aws_eks_access_policy_association" "additional_user_admin" {
#   cluster_name  = module.eks.cluster_name
#   principal_arn = "arn:aws:iam::637341921879:user/다른사용자이름"
#   policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
# 
#   access_scope {
#     type = "cluster"
#   }
# }

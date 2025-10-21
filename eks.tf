# EKS 클러스터 (Auto Mode)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.36.0"

  cluster_name    = local.project
  cluster_version = var.eks_cluster_version

  # EKS Auto Mode 활성화
  cluster_compute_config = {
    enabled       = true
    node_pools    = ["general-purpose"]
    node_role_arn = aws_iam_role.eks_auto_mode_node_role.arn
  }

  # 클러스터 엔드포인트(API 서버)에 퍼블릭 접근 허용
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  # 클러스터 보안그룹을 생성할 VPC
  vpc_id = module.vpc.vpc_id

  # 노드그룹/노드가 생성되는 서브넷
  subnet_ids = module.vpc.private_subnets

  # 컨트롤 플레인으로 연결될 ENI를 생성할 서브넷
  control_plane_subnet_ids = module.vpc.private_subnets

  # 클러스터를 생성한 IAM 객체에서 쿠버네티스 어드민 권한 할당
  enable_cluster_creator_admin_permissions = true

  create_kms_key              = false
  create_cloudwatch_log_group = false
  create_node_security_group  = false

  # 로깅 비활성화
  cluster_enabled_log_types = []
  # 암호화 비활성화
  cluster_encryption_config = {}

  depends_on = [
    module.vpc.natgw_ids,
    aws_iam_role.eks_auto_mode_node_role
  ]
}

# EKS Auto Mode용 노드 IAM 역할
resource "aws_iam_role" "eks_auto_mode_node_role" {
  name = "${local.project}-auto-mode-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_auto_mode_node_role_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ])

  policy_arn = each.value
  role       = aws_iam_role.eks_auto_mode_node_role.name
}

# EBS CSI 드라이버를 사용하는 스토리지 클래스 (Auto Mode에서 자동 설치됨)
resource "kubernetes_storage_class" "ebs_sc" {
  metadata {
    name = "ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [module.eks]
}

# 기본값으로 생성된 스토리지 클래스 해제
resource "kubernetes_annotations" "default_storageclass" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  force       = "true"

  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  depends_on = [
    kubernetes_storage_class.ebs_sc
  ]
}

/* 필수 라이브러리 */
# AWS Load Balancer Controller에 부여할 IAM 역할 및 Pod Identity Association
module "aws_load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "1.11.0"

  name = "aws-load-balancer-controller"

  attach_aws_lb_controller_policy = true

  associations = {
    (module.eks.cluster_name) = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = {
    app = "aws-load-balancer-controller"
  }
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_chart_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    clusterName: ${module.eks.cluster_name}
    vpcId: ${module.vpc.vpc_id}
    replicaCount: 1
    serviceAccount:
      create: true
    EOT
  ]

  depends_on = [
    module.eks,
    module.aws_load_balancer_controller_pod_identity
  ]
}

# ExternalDNS에 부여할 IAM 역할 및 Pod Identity Association
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "1.11.0"

  name = "external-dns"

  attach_external_dns_policy = true
  external_dns_hosted_zone_arns = [
    data.aws_route53_zone.this.arn
  ]

  associations = {
    (module.eks.cluster_name) = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
    }
  }

  tags = {
    app = "external-dns"
  }
}

# ExternalDNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: ${module.external_dns_pod_identity.iam_role_arn}
    txtOwnerId: ${module.eks.cluster_name}
    policy: sync
    resources:
      requests:
        memory: 100Mi
    EOT
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}

# Ingress NGINX를 설치할 네임스페이스
resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

# Ingress NGINX
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_chart_version
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/ingress-nginx.yaml", {
      lb_acm_certificate_arn = aws_acm_certificate_validation.this.certificate_arn
    })
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_acm_certificate_validation.this
  ]
}

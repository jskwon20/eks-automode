# EKS 클러스터 (Auto Mode)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.36.0"

  cluster_name    = local.project
  cluster_version = var.eks_cluster_version

  # EKS Auto Mode 활성화
  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # 클러스터 엔드포인트 설정
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # 클러스터를 생성한 IAM 객체에서 쿠버네티스 어드민 권한 할당
  enable_cluster_creator_admin_permissions = true

  # 노드 보안 그룹 직접 관리
  create_node_security_group = false
  node_security_group_id     = aws_security_group.eks_nodes_sg.id

  # 불필요한 리소스 생성 비활성화
  create_kms_key              = false
  create_cloudwatch_log_group = false

  cluster_enabled_log_types = []
  cluster_encryption_config = {}
}

# AWS Load Balancer Controller Pod Identity
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
    templatefile("${path.module}/helm-values/aws-load-balancer-controller-values.yaml", {
      cluster_name = module.eks.cluster_name
      vpc_id       = module.vpc.vpc_id
    })
  ]

  depends_on = [
    module.eks,
    module.aws_load_balancer_controller_pod_identity
  ]
}

# ExternalDNS Pod Identity
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
    templatefile("${path.module}/helm-values/external-dns-values.yaml", {
      iam_role_arn = module.external_dns_pod_identity.iam_role_arn
      cluster_name = module.eks.cluster_name
    })
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}

# Metrics Server
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    args:
      - --kubelet-insecure-tls
    EOT
  ]

  depends_on = [
    module.eks
  ]
}

# Ingress NGINX 네임스페이스
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
    templatefile("${path.module}/helm-values/ingres-values.yaml", {
      lb_acm_certificate_arn = aws_acm_certificate_validation.this.certificate_arn
    })
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_acm_certificate_validation.this
  ]
}

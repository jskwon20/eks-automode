# EKS 노드 보안 그룹
resource "aws_security_group" "eks_nodes_sg" {
  name        = "eks-nodes-sg"
  description = "Security group for EKS nodes"
  vpc_id      = module.vpc.vpc_id

  # 임시로 모든 인바운드 트래픽 허용 (테스트용)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "TEMP: Allow all inbound traffic (for testing)"
  }

  # 아웃바운드 트래픽 허용 (모두 허용)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-nodes-sg"
  }
}

# EKS 노드 간 통신 허용
resource "aws_security_group_rule" "eks_nodes_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.eks_nodes_sg.id
  description       = "Allow all traffic between nodes"
}

resource "aws_security_group_rule" "eks_nodes_ingress_control_plane_https_webhook" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes_sg.id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "Allow EKS access from nodes"
}

resource "aws_security_group_rule" "eks_nodes_ingress_metrics" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes_sg.id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "Allow EKS access from nodes"
}

# EKS 클러스터 보안 그룹에 모든 인바운드 트래픽 허용 (임시 테스트용)
resource "aws_security_group_rule" "eks_cluster_ingress_all" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.cluster_security_group_id
  description       = "TEMP: Allow all inbound traffic (for testing)"
}

resource "aws_security_group_rule" "eks_cluster_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.cluster_security_group_id
  description       = "TEMP: Allow all outbound traffic (for testing)"
}

# EKS 클러스터 보안 그룹에 EKS 컨트롤 플레인에서의 인바운드 트래픽 허용
resource "aws_security_group_rule" "eks_cluster_ingress_nodes_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = aws_security_group.eks_nodes_sg.id
  description              = "Allow nodes to communicate with control plane (HTTPS)"
}

# kubelet API 접근 허용 (노드에서 실행 중인 파드와의 통신)
resource "aws_security_group_rule" "eks_cluster_ingress_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = aws_security_group.eks_nodes_sg.id
  description              = "Allow kubelet communication from nodes"
}

# etcd 클라이언트 포트 (컨트롤 플레인 내부 통신)
resource "aws_security_group_rule" "eks_cluster_ingress_etcd" {
  type                     = "ingress"
  from_port                = 2379
  to_port                  = 2380
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "Allow etcd client/server communication between control plane nodes"
}

# CoreDNS를 위한 DNS 포트
resource "aws_security_group_rule" "eks_nodes_ingress_dns_tcp" {
  type                     = "ingress"
  from_port                = 53
  to_port                  = 53
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes_sg.id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "Allow DNS (TCP) from control plane"
}

resource "aws_security_group_rule" "eks_nodes_ingress_dns_udp" {
  type                     = "ingress"
  from_port                = 53
  to_port                  = 53
  protocol                 = "udp"
  security_group_id        = aws_security_group.eks_nodes_sg.id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "Allow DNS (UDP) from control plane"
}

resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  source_security_group_id = aws_security_group.eks_nodes_sg.id
  security_group_id        = module.eks.cluster_security_group_id
  description              = "Allow all traffic from EC2 nodes to the cluster security group"
}

resource "aws_security_group_rule" "cluster_ingress_self" {
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  self                     = true
  security_group_id        = module.eks.cluster_security_group_id
  description              = "Allow all traffic within the cluster security group"
}

# ACM 인증서
resource "aws_acm_certificate" "this" {
  domain_name       = "*.gsitm-test.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ACM 인증서 검증
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

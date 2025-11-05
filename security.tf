# EKS Auto Mode용 노드 보안 그룹
resource "aws_security_group" "eks_nodes_sg" {
  name        = "${local.project}-nodes-sg"
  description = "Security group for EKS Auto Mode nodes"
  vpc_id      = module.vpc.vpc_id

  # HTTP 접근 허용
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS 접근 허용
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 노드 간 통신 허용
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # 모든 아웃바운드 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.project}-nodes-sg"
  }
}

# 클러스터에서 노드로의 통신을 위한 별도 규칙
resource "aws_security_group_rule" "cluster_to_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = module.eks.cluster_security_group_id
  security_group_id        = aws_security_group.eks_nodes_sg.id

  depends_on = [module.eks]
}

# ACM 인증서
resource "aws_acm_certificate" "this" {
  domain_name       = "gsitm-test.com"
  subject_alternative_names = ["*.gsitm-test.com"]
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

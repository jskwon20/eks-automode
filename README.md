# 🛠️ Terraform 기반 AWS EKS Auto Mode 프로젝트

> EKS Auto Mode를 활용한 완전 관리형 Kubernetes 클러스터 구성

---

## 📌 프로젝트 개요

Amazon EKS Auto Mode는 노드 관리를 완전히 자동화하는 새로운 기능입니다.
기존의 수동 노드 관리나 Karpenter 설정의 복잡성을 해결하고, AWS가 모든 노드 운영을 담당합니다.

---

## 🎯 주요 특징

- **EKS Auto Mode**: 완전 관리형 노드 자동 관리
- **자동 스케일링**: 워크로드에 따른 노드 자동 생성/삭제
- **비용 최적화**: 사용하지 않는 노드 자동 제거
- **운영 부담 제로**: 노드 관리 작업 불필요

---

## 🧰 구성 요소

| 항목       | 내용                         |
|------------|------------------------------|
| IaC 도구    | Terraform                    |
| 클라우드    | AWS                          |
| 컨테이너    | Kubernetes (EKS Auto Mode)   |
| 네트워킹    | VPC, Subnets, NAT Gateway    |
| DNS        | Route53, ExternalDNS         |
| 로드밸런서  | AWS Load Balancer Controller |
| Ingress    | NGINX Ingress Controller     |

---

## 🚀 배포 방법

1. **변수 설정**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # terraform.tfvars 파일을 환경에 맞게 수정
   ```

2. **Terraform 배포**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **kubectl 설정**:
   ```bash
   aws eks update-kubeconfig --name <cluster-name> --region ap-northeast-2
   ```

---

## 📊 EKS Auto Mode 장점

- **완전 관리형**: AWS가 노드 프로비저닝, 스케일링, 패치를 자동 처리
- **비용 최적화**: 워크로드에 따른 자동 리소스 최적화
- **운영 부담 제로**: 노드 관리 작업 불필요
- **높은 가용성**: AWS의 지속적인 노드 상태 모니터링

---

## ⚠️ 주의사항

- EKS Auto Mode는 특정 리전에서만 사용 가능
- 일부 고급 노드 구성 옵션이 제한될 수 있음
- 기존 Karpenter 기반 클러스터에서 마이그레이션 시 주의 필요


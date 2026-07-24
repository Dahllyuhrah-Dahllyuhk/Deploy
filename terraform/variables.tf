variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "로컬 AWS CLI 프로파일 이름 (aws configure --profile 로 생성)"
  type        = string
  default     = "matuabom"
}

variable "project" {
  description = "프로젝트 이름 (리소스 네이밍 접두사)"
  type        = string
  default     = "matuabom"
}

variable "domain" {
  description = "루트 도메인 (기존 Route53 호스티드존)"
  type        = string
  default     = "matuabom.store"
}

variable "api_subdomain" {
  description = "API 서브도메인 (api.<domain> 형태로 EIP에 연결)"
  type        = string
  default     = "api"
}

variable "instance_type" {
  description = "ECS 컨테이너 인스턴스 타입 (프리티어: t3.micro)"
  type        = string
  default     = "t3.micro"
}

variable "github_repo" {
  description = "GitHub OIDC 대상 저장소 (owner/repo)"
  type        = string
  default     = "Dahllyuhrah-Dahllyuhk/BE"
}

variable "github_branch" {
  description = "GitHub Actions 배포 허용 브랜치"
  type        = string
  default     = "develop"
}

variable "ssh_cidr" {
  description = "SSH(22) 접근 허용 CIDR. 빈 문자열이면 22 포트를 열지 않음 (SSM Session Manager 사용 권장)"
  type        = string
  default     = ""
}

variable "container_image_tag" {
  description = "ECS 태스크가 사용할 ECR 이미지 태그"
  type        = string
  default     = "latest"
}

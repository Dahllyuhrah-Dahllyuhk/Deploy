output "eip_public_ip" {
  description = "API 서버 고정 공인 IP (Route53 A레코드 대상)"
  value       = aws_eip.api.public_ip
}

output "route53_name_servers" {
  description = "새 호스티드존의 네임서버 4개 — 도메인 등록기관 NS에 이 값을 지정해야 DNS가 이 존을 가리킨다"
  value       = aws_route53_zone.main.name_servers
}

output "ecr_repository_url" {
  description = "ECR 저장소 URL (CI/CD push 대상)"
  value       = aws_ecr_repository.be.repository_url
}

output "ecs_cluster_name" {
  description = "ECS 클러스터 이름"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS 서비스 이름"
  value       = aws_ecs_service.be.name
}

output "github_actions_role_arn" {
  description = "GitHub Actions OIDC 역할 ARN (secrets.AWS_ROLE_ARN 로 사용)"
  value       = aws_iam_role.github_actions.arn
}

output "instance_id" {
  description = "ECS 컨테이너 인스턴스 ID (SSM Session Manager 접속용)"
  value       = aws_instance.ecs.id
}

output "ssm_parameter_names" {
  description = "생성된 SSM 시크릿 파라미터 이름 목록 (실값 주입 대상)"
  value       = [for p in aws_ssm_parameter.secrets : p.name]
}

# CloudWatch 로그 그룹을 미리 생성한다.
# ECS 실행역할(AmazonECSTaskExecutionRolePolicy)은 CreateLogStream/PutLogEvents만 있고
# CreateLogGroup 권한이 없어, awslogs-create-group=true가 실패해 로그가 유실됐다.
# 그룹을 TF로 선생성하면 awslogs 드라이버가 기존 그룹에 스트림만 만들면 되므로 정상 동작한다.
resource "aws_cloudwatch_log_group" "be" {
  name              = "/${var.project}/be"
  retention_in_days = 14 # 사이드 프로젝트 — 짧게 유지해 비용 최소화
}

resource "aws_cloudwatch_log_group" "caddy" {
  name              = "/${var.project}/caddy"
  retention_in_days = 14
}

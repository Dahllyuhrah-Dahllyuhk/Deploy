# SSM Parameter Store SecureString 시크릿.
# placeholder("CHANGEME")로만 생성하고 실값은 Terraform이 관리하지 않는다.
# 실값 주입:
#   aws ssm put-parameter --name /matuabom/JWT_SECRET --type SecureString \
#     --value '...' --overwrite --profile matuabom
locals {
  ssm_secret_names = [
    "MONGODB_URI",
    "JWT_SECRET",
    "KAKAO_CLIENT_ID",
    "KAKAO_CLIENT_SECRET",
    "GOOGLE_CLIENT_ID",
    "GOOGLE_CLIENT_SECRET",
    "ADMIN_SECRET",
    "ENCRYPT_KEY",
    "GOOGLE_WEBHOOK_TOKEN",
  ]
}

resource "aws_ssm_parameter" "secrets" {
  for_each = toset(local.ssm_secret_names)

  name  = "/${var.project}/${each.value}"
  type  = "SecureString"
  value = "CHANGEME"

  lifecycle {
    # 실값은 사용자가 CLI로 주입하므로 Terraform은 값 변경을 무시한다.
    ignore_changes = [value]
  }

  tags = {
    Name = "/${var.project}/${each.value}"
  }
}

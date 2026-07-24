# Route53 호스티드존 — 새 계정에 신규 생성 (옛 계정 존은 폐기).
# apply 후 출력되는 name_servers 4개를 도메인 등록기관(레지스트라)의 NS로 지정해야
# 이 존이 실제로 권위를 갖는다.
resource "aws_route53_zone" "main" {
  name = var.domain

  tags = {
    Name = var.domain
  }
}

# api.matuabom.store -> EIP
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.api_fqdn
  type    = "A"
  ttl     = 300
  records = [aws_eip.api.public_ip]
}

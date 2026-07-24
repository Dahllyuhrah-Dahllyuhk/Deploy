# Route53 호스티드존 — 새 계정에 신규 생성 (옛 계정 존은 폐기).
# apply 후 출력되는 name_servers 4개를 도메인 등록기관(레지스트라)의 NS로 지정해야
# 이 존이 실제로 권위를 갖는다.
resource "aws_route53_zone" "main" {
  name = var.domain

  tags = {
    Name = var.domain
  }
}

# api.matuabom.store -> EIP (백엔드)
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.api_fqdn
  type    = "A"
  ttl     = 300
  records = [aws_eip.api.public_ip]
}

# 프론트(Vercel) — apex를 primary로 사용(백엔드 CORS가 apex 기준).
# 값은 Vercel Domains 설정 화면이 제시한 것. www는 apex로 308 리다이렉트되게 Vercel에서 설정.
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = ["216.198.79.1"] # Vercel apex A
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain}"
  type    = "CNAME"
  ttl     = 300
  records = ["f30d8d63236496b5.vercel-dns-017.com"] # Vercel www CNAME (프로젝트별 값)
}

# EC2(ECS 컨테이너 인스턴스)용 보안 그룹.
# 인바운드: 80/443 (Caddy가 처리). 22는 ssh_cidr가 있을 때만 (dynamic block).
# 8080은 열지 않음 — Caddy가 host localhost:8080 으로만 접근한다.
resource "aws_security_group" "ec2" {
  name        = "${var.project}-ec2-sg"
  description = "SG for matuabom ECS container instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.ssh_cidr == "" ? [] : [var.ssh_cidr]
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-ec2-sg"
  }
}

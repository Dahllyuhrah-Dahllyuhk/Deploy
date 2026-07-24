resource "aws_ecr_repository" "be" {
  name                 = "${var.project}-be"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project}-be"
  }
}

# 최근 3개 이미지만 유지 (프리티어 스토리지 절약).
resource "aws_ecr_lifecycle_policy" "be" {
  repository = aws_ecr_repository.be.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last 3 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 3
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

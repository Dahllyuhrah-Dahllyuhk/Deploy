# ECS-optimized Amazon Linux 2023 AMI id (SSM Public Parameter)
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
}

########################################
# EIP + 단일 EC2 컨테이너 인스턴스 (ASG 없음)
########################################
resource "aws_eip" "api" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-api-eip"
  }
}

locals {
  user_data = <<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
    mkdir -p /ecs/caddy-data
    # t3.micro(1GB)는 JVM+Caddy+OS에 빠듯 → 2GB swap로 OS 여유 확보 (OOM 예방)
    if [ ! -f /swapfile ]; then
      dd if=/dev/zero of=/swapfile bs=1M count=2048
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
  EOF
}

resource "aws_instance" "ecs" {
  ami                    = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ecs_instance.name
  user_data              = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  tags = {
    Name = "${var.project}-ecs-instance"
  }
}

resource "aws_eip_association" "api" {
  instance_id   = aws_instance.ecs.id
  allocation_id = aws_eip.api.id
}

########################################
# 태스크 정의 (network_mode = host, be + caddy)
########################################
locals {
  api_fqdn = "${var.api_subdomain}.${var.domain}"

  # SSM 시크릿을 태스크 정의 secrets[] 형태로 변환
  be_secrets = [
    for name in local.ssm_secret_names : {
      name      = name
      valueFrom = aws_ssm_parameter.secrets[name].arn
    }
  ]

  container_definitions = jsonencode([
    {
      name      = "be"
      image     = "${aws_ecr_repository.be.repository_url}:${var.container_image_tag}"
      essential = true
      memory    = 820 # 하드 한도. t3.micro(1GB)에서 caddy(96)+OS+ECS에이전트와 공존하는 상한.

      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        # 힙을 컨테이너 한도의 60%로 (Dockerfile 기본 75%는 t3.micro에서 non-heap과 합쳐 OOM 위험) → 힙 ~490MB
        { name = "JAVA_OPTS", value = "-XX:+UseContainerSupport -XX:MaxRAMPercentage=60.0" },
        { name = "MONGODB_NAME", value = "matuabom" },
        { name = "FRONTEND_ORIGIN", value = "https://${var.domain}" },
        { name = "BACKEND_BASE_URL", value = "https://${local.api_fqdn}" },
        { name = "COOKIE_SECURE", value = "true" },
        { name = "TZ", value = "Asia/Seoul" },
      ]

      secrets = local.be_secrets

      portMappings = [
        { containerPort = 8080, hostPort = 8080, protocol = "tcp" }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/${var.project}/be"
          "awslogs-create-group"  = "true"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "be"
        }
      }
    },
    {
      name      = "caddy"
      image     = "caddy:2-alpine"
      essential = true
      memory    = 96

      command = [
        "caddy", "reverse-proxy",
        "--from", local.api_fqdn,
        "--to", "localhost:8080"
      ]

      portMappings = [
        { containerPort = 80, hostPort = 80, protocol = "tcp" },
        { containerPort = 443, hostPort = 443, protocol = "tcp" }
      ]

      mountPoints = [
        { sourceVolume = "caddy-data", containerPath = "/data", readOnly = false }
      ]

      dependsOn = [
        { containerName = "be", condition = "START" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/${var.project}/caddy"
          "awslogs-create-group"  = "true"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "caddy"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "be" {
  family                   = "${var.project}-be"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # Caddy 인증서 영속용 host path 볼륨 (/ecs/caddy-data -> /data)
  volume {
    name      = "caddy-data"
    host_path = "/ecs/caddy-data"
  }

  container_definitions = local.container_definitions
}

########################################
# ECS 서비스 (launch_type = EC2, desired_count = 1). 로드밸런서 없음.
########################################
resource "aws_ecs_service" "be" {
  name            = "${var.project}-be"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.be.arn
  desired_count   = 1
  launch_type     = "EC2"

  # 단일 인스턴스이므로 새 태스크를 위한 여유 자원이 없다.
  # min 0% / max 100% = 기존 태스크를 먼저 stop 후 새 태스크 start (짧은 다운타임 허용).
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
}

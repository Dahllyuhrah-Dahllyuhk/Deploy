# matuabom 인프라 (Terraform)

프리티어 최적화된 맞춤봄(matuabom) 백엔드 재배포용 인프라 코드입니다.

단일 EC2(t3.micro) 위에 ECS(EC2 launch type)로 백엔드 컨테이너(`be`)와
리버스 프록시(`caddy`)를 띄우고, Caddy가 Let's Encrypt로 HTTPS를 자동 발급합니다.

**비용 최적화 원칙**: NAT Gateway / ALB / Fargate / RDS / ASG / 원격 state 백엔드를
사용하지 않습니다. state는 로컬 파일입니다.

## 아키텍처 요약

- **VPC** `10.0.0.0/16` + 퍼블릭 서브넷 2개(서로 다른 AZ), IGW, 퍼블릭 라우트테이블
- **EC2 1대**(t3.micro, ECS-optimized AL2023) — 퍼블릭 서브넷, EIP 연결, ECS 클러스터에 등록
- **ECS 태스크**(network_mode=host, 컨테이너 2개)
  - `be`: ECR 이미지, 8080 (Spring Boot)
  - `caddy`: `caddy:2-alpine`, 80/443 → `localhost:8080` 리버스 프록시, 자동 TLS
- **시크릿**: SSM Parameter Store(SecureString), 태스크 정의 `secrets[]`로 주입
- **DNS**: 기존 Route53 호스티드존 `matuabom.store` 참조, `api.matuabom.store` A레코드 → EIP
- **CI/CD**: GitHub OIDC 역할(ECR push + ECS 배포)

## 배포 순서

### 1. AWS 프로파일 설정

대상 계정 자격증명으로 프로파일을 만듭니다.

```bash
aws configure --profile matuabom
```

### 2. 초기화

```bash
cd terraform
terraform init
```

### 3. plan / apply

```bash
terraform plan
terraform apply
```

프로파일은 `variables.tf`의 `aws_profile`(기본 `matuabom`)을 사용합니다.
다른 프로파일을 쓰려면 `AWS_PROFILE=... terraform apply` 또는
`-var aws_profile=...`로 덮어쓰세요.

> **OIDC provider 주의**: 계정에 `token.actions.githubusercontent.com` OIDC
> provider가 이미 있으면 apply가 충돌합니다. 그럴 땐 먼저 import 하세요.
> ```bash
> terraform import aws_iam_openid_connect_provider.github \
>   arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com
> ```

### 4. 첫 배포 시 이미지 부재는 정상

ECR 저장소는 `apply`로 생성되지만, 이미지는 CI/CD(P3)가 push해야 합니다.
**최초에는 이미지가 없어 ECS 태스크가 실패하는 것이 정상**입니다.
GitHub Actions가 `latest` 태그를 push하면 서비스가 안정화됩니다.

### 5. SSM 시크릿 실값 주입

Terraform은 placeholder(`CHANGEME`)로만 파라미터를 생성합니다.
아래 9개를 실값으로 덮어쓰세요.

```bash
aws ssm put-parameter --name /matuabom/MONGODB_URI          --type SecureString --value '...' --overwrite --profile matuabom
aws ssm put-parameter --name /matuabom/JWT_SECRET           --type SecureString --value '...' --overwrite --profile matuabom
aws ssm put-parameter --name /matuabom/KAKAO_CLIENT_ID      --type SecureString --value '...' --overwrite --profile matuabom
aws ssm put-parameter --name /matuabom/KAKAO_CLIENT_SECRET  --type SecureString --value '...' --overwrite --profile matuabom
aws ssm put-parameter --name /matuabom/GOOGLE_CLIENT_ID     --type SecureString --value '...' --overwrite --profile matuabom
aws ssm put-parameter --name /matuabom/GOOGLE_CLIENT_SECRET --type SecureString --value '...' --overwrite --profile matuabom
aws ssm put-parameter --name /matuabom/ADMIN_SECRET         --type SecureString --value '...' --overwrite --profile matuabom
aws ssm put-parameter --name /matuabom/ENCRYPT_KEY          --type SecureString --value '...' --overwrite --profile matuabom
aws ssm put-parameter --name /matuabom/GOOGLE_WEBHOOK_TOKEN --type SecureString --value '...' --overwrite --profile matuabom
```

주입 후 서비스를 새 배포로 갱신하면 반영됩니다.

```bash
aws ecs update-service --cluster matuabom-cluster --service matuabom-be \
  --force-new-deployment --profile matuabom
```

### 6. DNS 구성

- `api.matuabom.store` → EIP (이 Terraform이 A레코드 생성)
- `matuabom.store`(프론트엔드) → Vercel (별도 관리, 이 Terraform 범위 밖)

### 7. Caddy 자동 TLS

`api.matuabom.store`가 EIP를 가리킨 뒤 인스턴스 첫 부팅에서 Caddy가
Let's Encrypt 인증서를 발급합니다. 인증서는 host path 볼륨
`/ecs/caddy-data`(→ 컨테이너 `/data`)에 영속되어 재시작 시 재발급하지 않습니다.

## 접속 (SSH 대체)

기본적으로 22 포트를 열지 않습니다. 인스턴스 접속은 SSM Session Manager를 사용하세요.

```bash
aws ssm start-session --target <instance_id> --profile matuabom
```

SSH가 필요하면 `ssh_cidr`에 본인 IP(예: `1.2.3.4/32`)를 지정해 apply 하세요.

## 정리 (destroy)

```bash
terraform destroy
```

ECR은 `force_delete=true`라 이미지가 있어도 삭제됩니다. EIP/Route53 레코드도 제거됩니다.

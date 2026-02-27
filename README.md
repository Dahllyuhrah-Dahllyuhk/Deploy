# 맞춰봄 배포 가이드

## 1. 서버 초기 세팅 (EC2 최초 1회)

```bash
# Docker, Docker Compose 설치
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker ubuntu

# AWS CLI 설치
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# 프로젝트 폴더 생성
mkdir -p /home/ubuntu/matuabom
cd /home/ubuntu/matuabom
```

## 2. .env 파일 생성 (서버에서 직접)

```bash
cd /home/ubuntu/matuabom
cp .env.example .env
nano .env  # 실제 값 입력
```

### JWT_SECRET 생성 방법
```bash
# 최소 64자 이상 랜덤 문자열
openssl rand -base64 64
```

## 3. SSL 인증서 발급 (Let's Encrypt)

```bash
sudo apt-get install -y certbot
sudo certbot certonly --standalone -d matuabom.store
# 이후 자동 갱신
sudo certbot renew --dry-run
```

## 4. ECR 로그인 & 배포

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  774023531956.dkr.ecr.ap-northeast-2.amazonaws.com

# 전체 서비스 시작
cd /home/ubuntu/matuabom
docker compose pull
docker compose up -d

# 로그 확인
docker compose logs -f be
docker compose logs -f fe
```

## 5. GitHub Actions Secrets 설정

GitHub 각 레포지토리 → Settings → Secrets and variables → Actions

| Secret | 설명 |
|--------|------|
| `AWS_REGION` | `ap-northeast-2` |
| `AWS_ACCOUNT_ID` | AWS 계정 ID |
| `AWS_ACCESS_KEY_ID` | IAM 액세스 키 |
| `AWS_SECRET_ACCESS_KEY` | IAM 시크릿 키 |
| `ECR_BE_REPO` | BE ECR 레포지토리 이름 |
| `ECR_FE_REPO` | FE ECR 레포지토리 이름 |
| `DEPLOY_HOST` | EC2 퍼블릭 IP |
| `DEPLOY_USER` | `ubuntu` |
| `DEPLOY_KEY` | EC2 SSH 프라이빗 키 |

## 6. 배포 흐름

```
main 브랜치 push
  └─ BE: build-push.yml → deploy.yml (자동)
  └─ FE: build-push.yml → deploy.yml (자동)
  └─ Deploy: deploy.yml → nginx reload (자동)
```

## 7. 보안 체크리스트

- [ ] `.env` 파일이 `.gitignore`에 포함되어 있는지 확인
- [ ] JWT_SECRET이 64자 이상인지 확인
- [ ] MongoDB 27017 포트가 외부에 노출되지 않는지 확인
- [ ] SSL 인증서 만료일 확인 (90일마다 자동 갱신)
- [ ] IAM 사용자에 최소 권한만 부여 (ECR push/pull 권한만)

## 8. 긴급 롤백

```bash
cd /home/ubuntu/matuabom

# 특정 버전으로 롤백
docker compose stop be
docker pull 774023531956.dkr.ecr.ap-northeast-2.amazonaws.com/matuabom-be:<이전-sha>
# docker-compose.yml의 image 태그를 이전 sha로 변경 후
docker compose up -d --no-deps be
```

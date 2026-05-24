# 맞춰봄 배포 가이드

## 1. 서버 초기 세팅 (EC2 최초 1회)

```bash
# 패키지 목록 업데이트 및 필수 패키지 설치
# unzip은 AWS CLI 설치 시 반드시 필요 — 누락 시 "unzip: command not found" 오류 발생
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin curl unzip

# Docker 그룹에 ubuntu 유저 추가 (재로그인 필요)
sudo usermod -aG docker ubuntu

# AWS CLI 설치
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# 프로젝트 폴더 생성
mkdir -p /home/ubuntu/Deploy
cd /home/ubuntu/Deploy
```

> ⚠️ `docker` 명령어 실행 시 `permission denied` 가 뜨면 EC2에 재접속 후 재시도

---

## 2. .env 파일 생성

```bash
cd /home/ubuntu/Deploy
cp .env.example .env
nano .env  # 실제 값 입력
```

### 필수 환경변수

| 변수 | 예시 / 설명 |
|------|------------|
| `POSTGRES_USER` | DB 사용자명 |
| `POSTGRES_PASSWORD` | DB 비밀번호 |
| `REDIS_PASSWORD` | Redis 비밀번호 |
| `JWT_SECRET` | 최소 64자 이상 랜덤 문자열 (`openssl rand -base64 64`) |
| `KAKAO_CLIENT_ID` | 카카오 앱 REST API 키 |
| `KAKAO_CLIENT_SECRET` | 카카오 Client Secret |
| `GOOGLE_CLIENT_ID` | Google OAuth 클라이언트 ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth 클라이언트 Secret |
| `GOOGLE_WEBHOOK_TOKEN` | Google Calendar Webhook 검증 토큰 (`openssl rand -hex 32`) |
| `FRONTEND_ORIGIN` | `https://matuabom.store` |
| `BACKEND_BASE_URL` | `https://matuabom.store` |
| `COOKIE_SECURE` | `true` (HTTPS 환경) |
| `DDL_AUTO` | `validate` (최초 테이블 생성 후 반드시 validate로 변경) |
| `SPRING_PROFILES_ACTIVE` | `prod` |
| `ADMIN_SECRET` | 관리자 API 시크릿 |
| `ENCRYPT_KEY` | 암호화 키 |

### JWT_SECRET 생성

```bash
openssl rand -base64 64
```

---

## 3. EBS 디스크 용량 확인 및 확장

EC2 인스턴스 스토리지가 부족하면 Docker pull/up 시 `no space left on device` 오류가 발생한다.

```bash
# 현재 디스크 사용량 확인
df -h

# 파티션 크기 확인 (AWS Console에서 볼륨 확장 후)
lsblk
```

AWS Console에서 EBS 볼륨 크기를 늘린 후 EC2 내부에서도 반드시 파티션을 확장해야 한다:

```bash
# 파티션 확장 (nvme0n1p1 은 lsblk 결과에 맞게 조정)
sudo growpart /dev/nvme0n1 1

# 파일시스템 확장
sudo resize2fs /dev/root

# 확인
df -h
```

### Docker 캐시 정리 (디스크 부족 시)

```bash
# 사용하지 않는 이미지·컨테이너·네트워크 정리
docker system prune -f

# 볼륨까지 포함해서 전체 정리 (데이터 삭제 주의)
docker system prune -a -f --volumes
```

> ⚠️ `docker system prune -a` 는 실행 중인 컨테이너를 제외한 모든 이미지를 삭제한다. 운영 중 실행 시 주의.

---

## 4. SSL 인증서 발급 (Let's Encrypt)

```bash
sudo apt-get install -y certbot

# 발급 (80 포트 일시 사용 — nginx 중지 후 실행)
sudo certbot certonly --standalone -d matuabom.store

# 자동 갱신 확인
sudo certbot renew --dry-run
```

---

## 5. ECR 로그인 & 초기 배포

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  978022759902.dkr.ecr.ap-northeast-2.amazonaws.com

# 전체 서비스 시작
cd /home/ubuntu/Deploy
docker compose pull
docker compose up -d

# 헬스체크 확인 (be가 healthy 될 때까지 대기)
docker compose ps

# 로그 확인
docker compose logs -f be
docker compose logs -f fe
```

> BE 헬스체크는 `curl -sf http://localhost:8080/actuator/health` 를 사용한다.
> `wget` 은 BE 이미지(Alpine)에 설치되어 있지 않으므로 docker-compose.yml에서 `wget` 사용 금지.

---

## 6. GitHub Actions Secrets 설정

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

---

## 7. 배포 흐름

```
main 브랜치 push
  └─ BE:     build-push.yml → docker system prune -f → pull → up --force-recreate
  └─ FE:     build-push.yml → docker system prune -f → pull → up --force-recreate
  └─ Deploy: deploy.yml     → docker system prune -f → pull → up → nginx reload
```

CI/CD가 자동으로 `docker system prune -f` 를 실행해 디스크 공간을 확보한 뒤 새 이미지를 pull 한다.

---

## 8. 수동 배포 / 서비스 재시작

```bash
cd /home/ubuntu/Deploy

# BE만 재배포
docker compose pull be
docker compose up -d --no-deps --force-recreate be

# FE만 재배포
docker compose pull fe
docker compose up -d --no-deps --force-recreate fe

# nginx 설정 변경 후 반드시 reload
docker compose exec nginx nginx -s reload
```

> ⚠️ BE 또는 FE 컨테이너 재시작 후 Docker 내부 IP가 바뀌면 nginx가 502를 반환할 수 있다.
> 이 경우 `docker compose exec nginx nginx -s reload` 로 업스트림 IP를 갱신한다.

---

## 9. 보안 체크리스트

- [ ] `.env` 파일이 `.gitignore`에 포함되어 있는지 확인
- [ ] `JWT_SECRET`이 64자 이상인지 확인
- [ ] MongoDB 27017, PostgreSQL 5432, Redis 6379 포트가 외부에 노출되지 않는지 확인 (EC2 보안 그룹)
- [ ] SSL 인증서 만료일 확인 (90일마다 자동 갱신)
- [ ] IAM 사용자에 최소 권한만 부여 (ECR push/pull 권한만)
- [ ] `DDL_AUTO=validate` 설정 확인 (최초 배포 후 `update` → `validate` 변경)

---

## 10. 긴급 롤백

```bash
cd /home/ubuntu/Deploy

# 특정 sha 이미지로 롤백
docker compose stop be
docker pull 978022759902.dkr.ecr.ap-northeast-2.amazonaws.com/matuabom-be:<이전-sha>
# docker-compose.yml의 image 태그를 이전 sha로 변경 후
docker compose up -d --no-deps be
```

---

## 11. 트러블슈팅

### `unzip: command not found`
AWS CLI 설치 시 발생. `sudo apt-get install -y unzip` 으로 해결.

### `no space left on device` (Docker pull/up 실패)
디스크 용량 부족. [3번 항목](#3-ebs-디스크-용량-확인-및-확장) 참고.
1. AWS Console에서 EBS 볼륨 크기 확장
2. `sudo growpart /dev/nvme0n1 1`
3. `sudo resize2fs /dev/root`
4. `docker system prune -f` 로 캐시 정리 후 재시도

### BE 헬스체크 `unhealthy`
`wget: not found` 오류가 원인인 경우, docker-compose.yml 헬스체크가 `curl` 을 사용하는지 확인:
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -sf http://localhost:8080/actuator/health || exit 1"]
```

### 502 Bad Gateway (컨테이너 재시작 후)
Docker 컨테이너 재시작으로 내부 IP가 변경되어 nginx 업스트림이 stale 상태.
```bash
docker compose exec nginx nginx -s reload
```

### `ConflictingBeanDefinitionException` (BE 기동 실패)
같은 클래스가 두 패키지 경로에 중복 등록된 경우. 브랜치 머지 후 구버전 파일이 잔존하는 것이 원인.
중복 파일을 `git rm` 으로 제거 후 재배포.

### SSE `/api/sse/events` 401 Unauthorized
복수의 원인이 복합적으로 작용할 수 있다:
1. **SecurityConfig** — `/api/sse/**` 가 `permitAll()` 로 설정되어 있는지 확인
2. **nginx** — SSE location 블록에 proxy 헤더가 모두 명시되어 있는지 확인
   (location 블록에 `proxy_set_header` 가 하나라도 있으면 server 레벨 헤더가 상속되지 않음)
3. **토큰 로테이션 race condition** — 동시 SSE 연결이 두 개 이상일 때 grace window 로직 확인

### 구글 캘린더 연동 후 이벤트가 표시되지 않음
FE에서 `/oauth2/authorization/google` 리다이렉트 전에
`POST /api/auth/prepare-google-link` 를 먼저 호출하는지 확인.
미호출 시 OAuth 콜백에서 userId 식별 불가 → `/login` 으로 redirect → 동기화 미실행.

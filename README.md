# Vibe Infra — 部署基础设施

Vibe 内容发布平台的后端部署配置。

## 架构

```
GitHub Actions (构建镜像) → GHCR (镜像仓库, public)
                                     ↓
用户 → 宿主机 Nginx (80/443 + SSL) → Docker vibe-api (127.0.0.1:3011)
                                              ↓
                                    阿里云 RDS (MySQL)
                                    七牛云 (对象存储)
```

**设计原则：**
- **服务器零构建** — GitHub Actions 负责构建镜像，服务器只拉取重启
- Nginx 由宿主机统一管理，不放入 Docker（避免端口冲突，方便多个服务共用）
- Docker 只运行 API 服务，轻量简洁
- MySQL 使用阿里云 RDS，存储使用七牛云，无需本地数据库

## CI/CD 流程

```
push to main → GitHub Actions 构建 Docker → 推送到 GHCR
                                                   ↓
                                          SSH 到服务器
                                          docker pull latest
                                          docker compose up -d
                                          健康检查 (6 次重试)
```

服务器无需安装 Go、无需克隆源码，只拉镜像即可。

## 目录结构

```
vibe-infra/
├── docker-compose.yml      # API 服务编排（使用 GHCR 镜像）
├── Dockerfile              # Go 多阶段构建（CI 使用）
├── .env.example            # 环境变量模板
├── .env                    # 实际配置（不入 Git）
├── nginx/
│   ├── nginx.conf          # Nginx 主配置（参考）
│   └── conf.d/
│       └── vibe.conf       # Vibe 反代配置（部署到宿主机）
├── scripts/
│   ├── deploy.sh           # 首次部署（Docker 构建 + Nginx）
│   ├── update.sh           # 更新重启（拉镜像 + 重启）
│   └── ssl.sh              # SSL 证书申请
├── templates/
│   └── config.prod.yaml    # 生产配置模板（${ENV_VAR} 展开）
├── ssl/                    # SSL 证书
└── logs/                   # 日志
```

## docker-compose.yml

服务器上使用镜像模式（不再是本地构建）：

```yaml
services:
  vibe-api:
    image: ghcr.io/youngcc2/vibe-server:latest
    container_name: vibe-api
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "127.0.0.1:3011:8080"
    networks:
      - vibe-net
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

networks:
  vibe-net:
    driver: bridge
```

## 前置要求

服务器上需要已安装：

| 组件 | 安装方式 | 说明 |
|------|---------|------|
| **Docker** | `curl -fsSL https://get.docker.com \| sh` | 20.10+，含 Compose |
| **Nginx** | `apt install nginx` | 宿主机统一管理 80/443 |
| **certbot** | `apt install certbot python3-certbot-nginx` | SSL 证书（可选） |

> 服务器**不需要**安装 Go、不需要克隆 vibe-server 源码。

## 首次部署

### 1. 克隆 infra 配置

```bash
cd /home
git clone https://github.com/YoungCC2/vibe-infra.git
```

### 2. 配置环境变量

```bash
cd vibe-infra
cp .env.example .env
vi .env
```

必填项：

| 变量 | 说明 |
|------|------|
| `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASSWORD` / `DB_NAME` | 阿里云 RDS 连接信息 |
| `QINIU_ACCESS_KEY` / `QINIU_SECRET_KEY` | 七牛云密钥 |
| `QINIU_BUCKET` / `QINIU_REGION` / `QINIU_DOMAIN` / `QINIU_PREFIX` | 七牛云存储配置 |
| `ACCESS_CODE` | PIN 码登录密码 |
| `JWT_SECRET` | JWT 签名密钥 |
| `CORS_ORIGINS` | 允许的跨域来源（逗号分隔） |
| `AI_PROVIDER` | AI 评价供应商：`glm` / `deepseek`（默认 deepseek） |
| `GLM_API_KEY` | GLM AI 评价 API Key |
| `DEEPSEEK_API_KEY` | DeepSeek AI 评价 API Key |

### 3. 拉取镜像并启动

```bash
docker pull ghcr.io/youngcc2/vibe-server:latest
docker compose up -d
```

### 4. 配置 Nginx 反代

```bash
cp nginx/conf.d/vibe.conf /etc/nginx/conf.d/
sed -i 's/YOUR_DOMAIN/your-domain.com/g' /etc/nginx/conf.d/vibe.conf
nginx -t && systemctl reload nginx
```

### 5. 配置 SSL 证书

```bash
./scripts/ssl.sh your-domain.com
```

## 日常运维

### 更新服务

CI/CD 会自动部署。如需手动更新：

```bash
cd /home/vibe-infra
docker pull ghcr.io/youngcc2/vibe-server:latest
docker compose up -d --force-recreate vibe-api
docker image prune -f
```

### 查看日志

```bash
docker compose logs -f vibe-api
```

### 停止/重启

```bash
docker compose down                    # 停止
docker compose up -d                   # 启动
docker compose restart vibe-api        # 重启
```

### 健康检查

```bash
curl http://127.0.0.1:3011/api/health
# {"status":"ok"}
```

## Nginx 配置

宿主机 Nginx 统一管理 80/443 + SSL，反代到 Docker 容器的 3011 端口。

关键配置：
- `client_max_body_size 600m`（图片 20MB / 视频 500MB）
- HTTP → HTTPS 自动跳转
- 安全头（HSTS / X-Frame-Options 等）

## GitHub Actions Secrets

CI/CD 部署所需的 Secrets（配置在 vibe-server repo）：

| Secret | 说明 |
|--------|------|
| `VIBE_SSH_HOST` | 服务器 IP 地址 |
| `VIBE_SSH_PORT` | SSH 端口（22） |
| `VIBE_SSH_USER` | SSH 用户（root） |
| `VIBE_SSH_KEY` | Deploy 专用 SSH 私钥（ed25519） |

## 故障排查

| 问题 | 排查方式 |
|------|---------|
| API 起不来 | `docker compose logs vibe-api` |
| 502 Bad Gateway | `curl http://127.0.0.1:3011/api/health` 检查容器是否运行 |
| 上传失败 | 检查七牛云配置和网络连通性 |
| 数据库连接失败 | 检查 RDS 白名单是否包含服务器 IP |
| AI 评价失败 | 检查 `GLM_API_KEY` 配置 |
| SSL 证书过期 | `certbot renew && systemctl reload nginx` |
| Docker 镜像拉不到 | 确认 GHCR package 为 public |

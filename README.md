# Vibe Infra

Vibe 个人日记本的部署基础设施 — Docker Compose + Nginx + 自动化脚本。

## 架构

```
                    ┌─────────────┐
   iOS App ────────►│   Nginx     │:443 (HTTPS)
                    │  反代 + SSL  │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  vibe-api   │:8080 (Go)
                    │  Gin + GORM │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ MySQL    │ │ 七牛云    │ │ Health   │
        │ 阿里云RDS │ │ 对象存储  │ │ /api/health│
        └──────────┘ └──────────┘ └──────────┘
```

**MySQL 和七牛云都是外部服务，不需要容器化。** Docker 只跑 API + Nginx。

## 目录结构

```
vibe-infra/
├── Dockerfile              # Go 后端多阶段构建 (golang:1.26 → alpine:3.20)
├── docker-compose.yml      # API + Nginx 编排
├── .env.example            # 环境变量模板（含真实 RDS host）
├── nginx/
│   ├── nginx.conf          # Nginx 全局配置
│   └── conf.d/
│       └── vibe.conf       # HTTPS 反代 + 安全头 + 健康检查
├── templates/
│   └── config.prod.yaml    # 生产配置唯一来源（${ENV_VAR} 注入，部署时自动同步到 vibe-server）
├── scripts/
│   ├── deploy.sh           # 首次一键部署
│   ├── update.sh           # 更新代码 + 自动迁移 + 滚动重启 + 健康检查
│   ├── migrate.sh          # 数据库迁移（Go / Docker fallback）
│   └── ssl.sh              # SSL 证书管理
├── ssl/                    # SSL 证书（gitignore）
├── logs/                   # Nginx 日志（gitignore）
└── README.md
```

## 快速部署

### 前置条件

- 云服务器（已安装 Docker + Docker Compose）
- vibe-server 代码已 clone 到服务器（同级目录）
- MySQL RDS 白名单已配置服务器 IP
- 七牛云 Bucket + AK/SK + CDN 域名已准备好
- 域名已解析到服务器 IP（如需 HTTPS）

### 1. 目录结构

```
zywoo/
├── vibe-server/      # 后端代码
└── vibe-infra/       # 本仓库
```

### 2. 配置环境变量

```bash
cp .env.example .env
vi .env
```

必填项：

| 变量 | 说明 |
|------|------|
| `DB_HOST` / `DB_USER` / `DB_PASSWORD` | 阿里云 RDS 连接信息 |
| `QINIU_ACCESS_KEY` / `QINIU_SECRET_KEY` | 七牛云密钥 |
| `QINIU_BUCKET` / `QINIU_DOMAIN` | 七牛云 Bucket 和 CDN 域名 |
| `ACCESS_CODE` | App 登录 PIN 码（改掉默认值！） |
| `JWT_SECRET` | JWT 签名密钥（`openssl rand -hex 32`） |
| `CORS_ORIGINS` | 允许的 CORS 源（逗号分隔，如 `https://api.example.com`） |

### 3. 一键部署

```bash
./scripts/deploy.sh
```

### 4. 配置 SSL

```bash
# 自签名（测试用）
./scripts/ssl.sh self-signed

# Let's Encrypt（正式域名）
./scripts/ssl.sh api.yourdomain.com
```

## 日常运维

### 更新代码

```bash
# 拉取代码 → 自动迁移 → 重新构建 → 滚动重启 → 健康检查
./scripts/update.sh
```

### 数据库迁移

```bash
./scripts/migrate.sh
```

### 查看日志

```bash
docker compose logs -f vibe-api     # API 日志
docker compose logs -f vibe-nginx   # Nginx 日志
```

### 停止 / 重启

```bash
docker compose down      # 停止
docker compose restart   # 重启
```

## 配置说明

### Dockerfile

多阶段构建：
1. `golang:1.26-alpine` — 编译 Go 二进制（CGO 禁用）
2. `alpine:3.20` — 运行时镜像（~20MB）

内置 HEALTHCHECK 打 `/api/health`（无需认证）。

### config.prod.yaml

**唯一来源** 是 `vibe-infra/templates/config.prod.yaml`。`deploy.sh` / `update.sh` 在构建前会自动把它拷贝到 `vibe-server/config.prod.yaml`（即 Docker 构建上下文），由 Dockerfile 复制为容器内的 `/app/config.yaml`。

> ⚠️ 不要手动编辑 `vibe-server/config.prod.yaml`——它是生成产物，每次部署都会被模板覆盖。所有生产配置改动都应改 `templates/config.prod.yaml`。
>
> 如果绕过脚本直接 `docker compose build`，需先手动执行：
> `cp templates/config.prod.yaml ../vibe-server/config.prod.yaml`

支持环境变量注入：
- `${VAR}` — 必须设置，否则为空
- `${VAR:-default}` — 有默认值
- 含 YAML 特殊字符的值自动加双引号

### Nginx 配置

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `client_max_body_size` | 600m | 支持大视频上传 |
| `proxy_read_timeout` | 120s | 上传超时保护 |
| HSTS | 1年 | 强制 HTTPS |
| HTTP/2 | 开启 | 提升并发性能 |
| Gzip | 开启 | 压缩 JSON 响应 |
| 健康检查 | `/health` | 打到 `/api/health`，无需认证 |

### Docker Compose 服务

| 服务 | 镜像 | 端口 | 说明 |
|------|------|------|------|
| vibe-api | 自构建 | 127.0.0.1:8080 | Go API，仅本地监听 |
| vibe-nginx | nginx:1.27 | 80, 443 | 对外服务，反代 API |

## 安全注意事项

1. **`.env` 不入 Git** — 含数据库密码和七牛云密钥
2. **SSL 证书不入 Git** — 已在 `.gitignore`
3. **生产环境改 ACCESS_CODE** — 不要用默认值
4. **JWT_SECRET 用随机字符串** — `openssl rand -hex 32`
5. **MySQL 白名单** — 只授权服务器 IP
6. **CORS_ORIGINS** — 生产环境必须配置，不要留空

## 故障排查

**API 启动失败：**
```bash
docker compose logs vibe-api
# 常见：数据库连接失败 → 检查 .env 和 RDS 白名单
```

**Nginx 502：**
```bash
docker compose logs vibe-nginx
# 常见：API 还没启动 → 等几秒，Docker 会自动重启
```

**健康检查失败：**
```bash
curl http://localhost/api/health
# 应返回 {"status":"ok"}
```

**上传失败：**
```bash
# 检查 Nginx body 大小限制（600m）
# 检查七牛云 AK/SK
# 检查文件类型是否被 magic bytes 校验拒绝
```

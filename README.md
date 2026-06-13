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
        │ MySQL    │ │ 七牛云    │ │ (外部)   │
        │ 阿里云RDS │ │ 对象存储  │ │          │
        └──────────┘ └──────────┘ └──────────┘
```

**MySQL 和七牛云都是外部服务，不需要容器化。** Docker 只跑 API + Nginx。

## 目录结构

```
vibe-infra/
├── Dockerfile              # Go 后端多阶段构建
├── docker-compose.yml      # API + Nginx 编排
├── .env.example            # 环境变量模板
├── nginx/
│   ├── nginx.conf          # Nginx 全局配置
│   └── conf.d/
│       └── vibe.conf       # HTTPS 反代 + 安全头
├── templates/
│   └── config.prod.yaml    # 生产配置（环境变量注入）
├── scripts/
│   ├── deploy.sh           # 一键部署
│   ├── update.sh           # 更新代码 + 滚动重启
│   ├── migrate.sh          # 数据库迁移
│   └── ssl.sh              # SSL 证书管理
├── ssl/                    # SSL 证书（gitignore）
├── logs/                   # Nginx 日志（gitignore）
└── README.md
```

## 快速部署

### 前置条件

- 云服务器（已安装 Docker + Docker Compose）
- vibe-server 代码已 clone 到服务器
- MySQL RDS 白名单已配置服务器 IP
- 七牛云 Bucket + AK/SK 已准备好

### 1. 克隆仓库

```bash
git clone https://github.com/YoungCC2/vibe-infra.git
```

确保目录关系：

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

填入真实的数据库密码、七牛云 AK/SK、JWT Secret 等。

### 3. 一键部署

```bash
./scripts/deploy.sh
```

脚本会自动：检查环境 → 构建镜像 → 启动服务 → 健康检查

### 4. 配置 SSL（可选）

```bash
# 自签名（测试用）
./scripts/ssl.sh self-signed

# 或 Let's Encrypt（正式域名）
./scripts/ssl.sh api.yourdomain.com
```

## 日常运维

### 更新代码

```bash
# 拉取最新代码 + 重新构建 + 滚动重启（零停机）
./scripts/update.sh
```

### 数据库迁移

```bash
./scripts/migrate.sh
```

### 查看日志

```bash
# 实时日志
docker compose logs -f

# 仅 API
docker compose logs -f vibe-api

# Nginx 访问日志
cat logs/nginx/access.log
```

### 停止 / 重启

```bash
# 停止
docker compose down

# 重启
docker compose restart
```

## Nginx 配置要点

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `client_max_body_size` | 600m | 支持大视频上传 |
| `proxy_read_timeout` | 120s | 上传超时保护 |
| HSTS | 1年 | 强制 HTTPS |
| HTTP/2 | 开启 | 提升并发性能 |
| Gzip | 开启 | 压缩 JSON 响应 |

## Docker Compose 服务

| 服务 | 镜像 | 端口 | 说明 |
|------|------|------|------|
| vibe-api | 自构建 | 127.0.0.1:8080 | Go API，仅本地监听 |
| vibe-nginx | nginx:1.27 | 80, 443 | 对外服务，反代 API |

**vibe-api 只绑定 127.0.0.1**，外部无法直接访问，必须通过 Nginx。

## 安全注意事项

1. **`.env` 文件不入 Git** — 包含数据库密码和七牛云密钥
2. **SSL 证书不入 Git** — 已在 `.gitignore` 中
3. **生产环境改 ACCESS_CODE** — 不要用默认的 `vibe123`
4. **JWT_SECRET 用随机字符串** — `openssl rand -hex 32`
5. **MySQL 白名单** — 只授权服务器 IP，不开放 0.0.0.0/0
6. **定期备份** — RDS 自动备份 + 七牛云存储冗余

## 故障排查

**API 启动失败：**
```bash
docker compose logs vibe-api
# 常见：数据库连接失败 → 检查 .env 和白名单
```

**Nginx 502：**
```bash
docker compose logs vibe-nginx
# 常见：API 还没启动 → 等几秒，docker compose 会自动重启
```

**上传失败：**
```bash
# 检查 Nginx body 大小限制
# 检查七牛云 AK/SK 是否正确
```

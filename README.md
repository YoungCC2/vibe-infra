# Vibe Infra — 部署基础设施

Vibe 内容发布平台的后端部署配置。

## 架构

```
用户 → 宿主机 Nginx (80/443 + SSL) → Docker vibe-api (127.0.0.1:3010)
                                              ↓
                                    阿里云 RDS (MySQL)
                                    七牛云 (对象存储)
```

**设计原则：**
- Nginx 由宿主机统一管理，不放入 Docker（避免端口冲突，方便多个服务共用）
- Docker 只运行 API 服务，轻量简洁
- MySQL 使用阿里云 RDS，存储使用七牛云，无需本地数据库

## 目录结构

```
vibe-infra/
├── docker-compose.yml      # API 服务编排
├── Dockerfile              # Go 多阶段构建
├── .env.example            # 环境变量模板
├── nginx/
│   ├── nginx.conf          # Nginx 主配置（参考）
│   └── conf.d/
│       └── vibe.conf       # Vibe 反代配置（部署到宿主机）
├── scripts/
│   ├── deploy.sh           # 一键部署
│   ├── update.sh           # 更新重启
│   └── ssl.sh              # SSL 证书申请
├── templates/
│   └── config.prod.yaml    # 生产配置模板
├── ssl/                    # SSL 证书（仅自签名时用）
└── logs/                   # 日志
```

## 前置要求

服务器上需要已安装：

| 组件 | 安装方式 | 说明 |
|------|---------|------|
| **Docker** | `curl -fsSL https://get.docker.com \| sh` | 20.10+，含 Compose |
| **Nginx** | `apt install nginx` | 宿主机统一管理 80/443 |
| **certbot** | `apt install certbot python3-certbot-nginx` | SSL 证书（可选，正式部署需要） |

## 快速部署

### 1. 克隆代码

```bash
cd /opt
git clone https://github.com/YoungCC2/vibe-server.git
git clone https://github.com/YoungCC2/vibe-infra.git
```

确保两个目录同级：
```
/opt/
├── vibe-server/
└── vibe-infra/
```

### 2. 配置环境变量

```bash
cd vibe-infra
cp .env.example .env
vi .env
```

必填项：
- `DB_DSN` — 阿里云 RDS 连接串
- `QINIU_AK` / `QINIU_SK` — 七牛云密钥
- `QINIU_BUCKET` — 七牛云 bucket 名
- `QINIU_DOMAIN` — 七牛云 CDN 域名
- `ACCESS_CODE` — 管理员 PIN 码
- `JWT_SECRET` — JWT 签名密钥
- `CORS_ORIGINS` — 允许的跨域来源

### 3. 一键部署

```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
```

### 4. 配置 Nginx 反代

```bash
# 复制配置到宿主机 Nginx
cp nginx/conf.d/vibe.conf /etc/nginx/conf.d/

# 替换域名（把 your-domain.com 换成真实域名）
sed -i 's/YOUR_DOMAIN/your-domain.com/g' /etc/nginx/conf.d/vibe.conf

# 测试并重载
nginx -t && systemctl reload nginx
```

### 5. 配置 SSL 证书

```bash
./scripts/ssl.sh your-domain.com
```

会自动通过 Let's Encrypt 申请证书并配置 Nginx。

## 日常运维

### 更新代码

```bash
./scripts/update.sh
```

自动拉取最新代码 → 同步配置 → 重新构建 → 重启 → 健康检查。

### 查看日志

```bash
docker compose logs -f
```

### 停止/重启

```bash
docker compose down      # 停止
docker compose up -d     # 启动
docker compose restart   # 重启
```

## 关于 Nginx

本项目 **不包含 Docker Nginx**，原因：

1. 服务器通常已有 Nginx 在运行（管理多个站点）
2. Docker 内再跑 Nginx 会导致 80/443 端口冲突
3. 宿主机 Nginx 统一管理 SSL 证书更方便

`nginx/` 目录提供配置模板，部署时复制到宿主机的 `/etc/nginx/conf.d/` 即可。

## GOPROXY 说明

Dockerfile 内已设置 `GOPROXY=https://goproxy.cn,direct`，确保国内服务器拉取 Go 依赖不会超时。如果你在海外服务器部署，可以改成 `https://proxy.golang.org,direct`。

## 故障排查

| 问题 | 排查方式 |
|------|---------|
| API 起不来 | `docker compose logs vibe-api` |
| 502 Bad Gateway | 检查 API 是否运行：`curl http://127.0.0.1:8080/api/health` |
| 上传失败 | 检查七牛云配置和网络连通性 |
| 数据库连接失败 | 检查 RDS 白名单是否包含服务器 IP |
| SSL 证书过期 | `certbot renew && systemctl reload nginx` |

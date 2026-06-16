#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe 一键部署脚本
# 在云服务器上执行
# 前提：宿主机已安装 Nginx 和 Docker
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$INFRA_DIR/../vibe-server"
DOMAIN="${VIBE_DOMAIN:-}"

echo "🚀 Vibe 部署开始"
echo "   Infra 目录: $INFRA_DIR"
echo ""

# 0. 检查 vibe-server 代码目录
if [ ! -d "$SERVER_DIR" ]; then
    echo "❌ 未找到 vibe-server 目录: $SERVER_DIR"
    echo "   请确保 vibe-server 与 vibe-infra 处于同级目录"
    exit 1
fi

# 1. 检查 .env
if [ ! -f "$INFRA_DIR/.env" ]; then
    echo "❌ 未找到 .env 文件"
    echo "   请复制 .env.example 并填写真实值："
    echo "   cp $INFRA_DIR/.env.example $INFRA_DIR/.env"
    echo "   vi $INFRA_DIR/.env"
    exit 1
fi

# 2. 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装"
    echo "   安装：curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose 未安装"
    echo "   Docker 20.10+ 自带 compose 插件"
    exit 1
fi

# 3. 检查宿主机 Nginx
if ! command -v nginx &> /dev/null; then
    echo "❌ 宿主机 Nginx 未安装"
    echo "   安装：apt install nginx"
    exit 1
fi

echo "   ✓ 宿主机 Nginx 已安装"

# 4. 同步生产配置
echo ""
echo "🧩 同步生产配置..."
cp "$INFRA_DIR/templates/config.prod.yaml" "$SERVER_DIR/config.prod.yaml"
echo "   ✓ config.prod.yaml 已同步到构建上下文"

# 5. 构建并启动 API
echo ""
echo "📦 构建 Docker 镜像..."
docker compose -f "$INFRA_DIR/docker-compose.yml" build

echo ""
echo "🔄 启动 API 服务..."
docker compose -f "$INFRA_DIR/docker-compose.yml" up -d

# 6. 检查 Nginx 配置
NGINX_VIBE_CONF="/etc/nginx/conf.d/vibe.conf"
if [ ! -f "$NGINX_VIBE_CONF" ]; then
    echo ""
    echo "⚠️  未找到 $NGINX_VIBE_CONF"
    echo "   请复制 Nginx 配置并修改域名："
    echo "   cp $INFRA_DIR/nginx/conf.d/vibe.conf $NGINX_VIBE_CONF"
    echo "   vi $NGINX_VIBE_CONF  # 修改 YOUR_DOMAIN"
    echo "   nginx -t && systemctl reload nginx"
    echo ""
    echo "   SSL 证书请运行: $INFRA_DIR/scripts/ssl.sh your-domain.com"
fi

# 7. 等待启动
echo ""
echo "⏳ 等待服务启动..."
sleep 3

# 8. 健康检查（直接检查 API 端口）
echo ""
echo "🩺 健康检查..."
for i in 1 2 3 4 5; do
    if curl -sf http://127.0.0.1:3010/api/health > /dev/null 2>&1; then
        echo "   ✅ API 服务健康"
        break
    fi
    echo "   等待中... ($i/5)"
    sleep 2
done

# 9. 状态
echo ""
echo "📊 服务状态:"
docker compose -f "$INFRA_DIR/docker-compose.yml" ps

echo ""
echo "✅ 部署完成！"
echo ""
echo "   API 直连:  http://127.0.0.1:3010/api"
echo "   通过 Nginx: https://YOUR_DOMAIN/api"
echo "   日志:  docker compose -f $INFRA_DIR/docker-compose.yml logs -f"
echo "   停止:  docker compose -f $INFRA_DIR/docker-compose.yml down"
echo ""
echo "   下一步:"
echo "     1. 配置 Nginx: cp $INFRA_DIR/nginx/conf.d/vibe.conf /etc/nginx/conf.d/"
echo "     2. 修改域名后: nginx -t && systemctl reload nginx"
echo "     3. 配置 SSL:  $INFRA_DIR/scripts/ssl.sh your-domain.com"

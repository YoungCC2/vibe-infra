#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe 一键部署脚本
# 在云服务器上执行
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$INFRA_DIR/../vibe-server"

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

# 3. 检查 SSL 证书
if [ ! -f "$INFRA_DIR/ssl/fullchain.pem" ]; then
    echo "⚠️  未找到 SSL 证书 ($INFRA_DIR/ssl/fullchain.pem)"
    echo "   生成自签名证书用于测试？(y/N)"
    read -r reply
    if [ "$reply" = "y" ] || [ "$reply" = "Y" ]; then
        mkdir -p "$INFRA_DIR/ssl"
        openssl req -x509 -nodes -days 365 \
            -newkey rsa:2048 \
            -keyout "$INFRA_DIR/ssl/privkey.pem" \
            -out "$INFRA_DIR/ssl/fullchain.pem" \
            -subj "/CN=localhost"
        echo "   ✓ 自签名证书已生成"
    else
        echo "   跳过 SSL（Nginx 会启动失败，请后续配置）"
    fi
fi

# 4. 同步生产配置（单一来源：templates/config.prod.yaml）
echo ""
echo "🧩 同步生产配置..."
cp "$INFRA_DIR/templates/config.prod.yaml" "$SERVER_DIR/config.prod.yaml"
echo "   ✓ config.prod.yaml 已同步到构建上下文"

# 5. 构建并启动
echo ""
echo "📦 构建 Docker 镜像..."
docker compose -f "$INFRA_DIR/docker-compose.yml" build

echo ""
echo "🔄 启动服务..."
docker compose -f "$INFRA_DIR/docker-compose.yml" up -d

# 6. 等待启动
echo ""
echo "⏳ 等待服务启动..."
sleep 3

# 7. 健康检查
echo ""
echo "🩺 健康检查..."
for i in 1 2 3 4 5; do
    if curl -sf http://localhost/health > /dev/null 2>&1; then
        echo "   ✅ 服务健康"
        break
    elif curl -sf http://localhost:8080/api/stats > /dev/null 2>&1; then
        echo "   ✅ API 已启动（Nginx 可能还在初始化）"
        break
    fi
    echo "   等待中... ($i/5)"
    sleep 2
done

# 8. 状态
echo ""
echo "📊 服务状态:"
docker compose -f "$INFRA_DIR/docker-compose.yml" ps

echo ""
echo "✅ 部署完成！"
echo ""
echo "   API:   http://$(curl -sf ifconfig.me 2>/dev/null || echo 'your-server-ip'):8080/api"
echo "   日志:  docker compose -f $INFRA_DIR/docker-compose.yml logs -f"
echo "   停止:  docker compose -f $INFRA_DIR/docker-compose.yml down"

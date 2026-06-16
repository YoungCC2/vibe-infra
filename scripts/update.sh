#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe 更新脚本 — 拉取最新代码并重新部署
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$INFRA_DIR/../vibe-server"

echo "🔄 Vibe 更新开始"
echo ""

# 1. 拉取最新代码
echo "📥 拉取 vibe-server..."
git -C "$SERVER_DIR" pull
echo "📥 拉取 vibe-infra..."
git -C "$INFRA_DIR" pull

# 2. 同步生产配置
echo ""
echo "🧩 同步生产配置..."
cp "$INFRA_DIR/templates/config.prod.yaml" "$SERVER_DIR/config.prod.yaml"

# 3. 重新构建并启动
echo ""
echo "📦 重新构建..."
docker compose -f "$INFRA_DIR/docker-compose.yml" build

echo ""
echo "🔄 重启服务..."
docker compose -f "$INFRA_DIR/docker-compose.yml" up -d

# 4. 健康检查
echo ""
echo "⏳ 等待服务启动..."
sleep 3

echo "🩺 健康检查..."
for i in 1 2 3 4 5; do
    if curl -sf http://127.0.0.1:3010/api/health > /dev/null 2>&1; then
        echo "   ✅ 服务健康"
        break
    fi
    echo "   等待中... ($i/5)"
    sleep 2
done

# 5. 状态
echo ""
echo "📊 服务状态:"
docker compose -f "$INFRA_DIR/docker-compose.yml" ps

echo ""
echo "✅ 更新完成！"

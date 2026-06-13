#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe 更新脚本 — 拉取最新代码 + 重新构建 + 滚动重启
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$INFRA_DIR/../vibe-server"

echo "🔄 Vibe 更新流程"
echo ""

# 1. 拉取最新代码
echo "📥 拉取最新代码..."
cd "$SERVER_DIR"
git pull origin main
echo "   ✓ 代码已更新"

# 2. 重新构建并重启
echo ""
echo "📦 重新构建 Docker 镜像..."
cd "$INFRA_DIR"
docker compose build vibe-api

echo ""
echo "🔄 重启服务（零停机）..."
docker compose up -d --no-deps vibe-api

# 3. 健康检查
echo ""
echo "🩺 健康检查..."
sleep 2
for i in 1 2 3 4 5; do
    if curl -sf http://localhost:8080/api/stats > /dev/null 2>&1; then
        echo "   ✅ 服务已恢复"
        exit 0
    fi
    echo "   等待中... ($i/5)"
    sleep 2
done

echo "   ⚠️  服务未就绪，检查日志："
echo "   docker compose -f $INFRA_DIR/docker-compose.yml logs vibe-api"
exit 1

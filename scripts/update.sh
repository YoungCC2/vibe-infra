#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe 更新脚本 — 拉取最新镜像并重启
# 镜像由 GitHub Actions 自动构建推送
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔄 Vibe 更新开始"
echo ""

# 1. 拉取最新镜像
echo "📥 拉取最新镜像..."
docker compose -f "$INFRA_DIR/docker-compose.yml" pull

# 2. 重启服务
echo ""
echo "🔄 重启服务..."
docker compose -f "$INFRA_DIR/docker-compose.yml" up -d

# 3. 健康检查
echo ""
echo "⏳ 等待服务启动..."
sleep 3

echo "🩺 健康检查..."
for i in 1 2 3 4 5; do
    if curl -sf http://127.0.0.1:3011/api/health > /dev/null 2>&1; then
        echo "   ✅ 服务健康"
        break
    fi
    echo "   等待中... ($i/5)"
    sleep 2
done

# 4. 状态
echo ""
echo "📊 服务状态:"
docker compose -f "$INFRA_DIR/docker-compose.yml" ps

# 5. 清理旧镜像
echo ""
echo "🧹 清理旧镜像..."
docker image prune -f 2>/dev/null || true

echo ""
echo "✅ 更新完成！"

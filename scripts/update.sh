#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe 更新脚本 — 拉取最新代码 + 迁移 + 重新构建 + 滚动重启
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

# 2. 执行数据库迁移
echo ""
echo "🗄️  执行数据库迁移..."
cd "$SERVER_DIR"
if [ -f "$INFRA_DIR/.env" ]; then
    set -a
    source "$INFRA_DIR/.env"
    set +a
fi
if command -v go &> /dev/null; then
    go build -o /tmp/vibe-migrate ./cmd/migrate/ && /tmp/vibe-migrate && echo "   ✓ 迁移完成" || echo "   ⚠️ 迁移跳过（可能已全部执行）"
else
    echo "   ⚠️ Go 未安装，跳过迁移。请手动执行 migrate。"
fi

# 3. 重新构建并重启
echo ""
echo "📦 重新构建 Docker 镜像..."
cd "$INFRA_DIR"
docker compose build vibe-api

echo ""
echo "🔄 重启服务（零停机）..."
docker compose up -d --no-deps vibe-api

# 4. 健康检查
echo ""
echo "🩺 健康检查..."
sleep 2
for i in 1 2 3 4 5; do
    if curl -sf http://localhost/health > /dev/null 2>&1; then
        echo "   ✅ 服务已恢复"
        exit 0
    fi
    echo "   等待中... ($i/5)"
    sleep 2
done

echo "   ⚠️  服务未就绪，检查日志："
echo "   docker compose -f $INFRA_DIR/docker-compose.yml logs vibe-api"
exit 1

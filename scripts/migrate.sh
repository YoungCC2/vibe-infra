#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe 数据库迁移脚本
# 在服务器上执行，初始化/升级 MySQL 表结构
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$INFRA_DIR/../vibe-server"

if [ ! -d "$SERVER_DIR" ]; then
    echo "❌ 未找到 vibe-server 目录: $SERVER_DIR"
    exit 1
fi

echo "🗄️  Vibe 数据库迁移"

# 加载环境变量
if [ -f "$INFRA_DIR/.env" ]; then
    set -a
    source "$INFRA_DIR/.env"
    set +a
    echo "   ✓ 已加载 .env"
else
    echo "   ⚠️  未找到 .env，使用环境变量"
fi

cd "$SERVER_DIR"

# 优先用 Go 直接编译运行
if command -v go &> /dev/null; then
    echo "📦 编译迁移工具..."
    go build -o /tmp/vibe-migrate ./cmd/migrate/

    echo "🔄 执行迁移..."
    /tmp/vibe-migrate
else
    echo "⚠️  Go 未安装，尝试通过 Docker 运行..."
    docker run --rm \
        --env-file "$INFRA_DIR/.env" \
        -v "$SERVER_DIR/migrations:/app/migrations" \
        -w /app \
        "$(docker compose -f "$INFRA_DIR/docker-compose.yml" config --images vibe-api 2>/dev/null || echo vibe-api:latest)" \
        /app/vibe-server migrate 2>/dev/null || {
        echo "❌ 无法通过 Docker 运行迁移"
        echo "   请在有 Go 环境的机器上执行: go run ./cmd/migrate/"
        exit 1
    }
fi

echo ""
echo "✅ 数据库迁移完成"

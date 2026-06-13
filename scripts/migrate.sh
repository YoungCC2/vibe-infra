#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe 数据库迁移脚本
# 在本地或服务器上执行，初始化 MySQL 表结构
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$INFRA_DIR/../vibe-server"

if [ ! -d "$SERVER_DIR" ]; then
    echo "❌ 未找到 vibe-server 目录: $SERVER_DIR"
    exit 1
fi

echo "🗄️  Vibe 数据库迁移"
echo "   Server 目录: $SERVER_DIR"
echo ""

# 加载环境变量
if [ -f "$INFRA_DIR/.env" ]; then
    set -a
    source "$INFRA_DIR/.env"
    set +a
    echo "   ✓ 已加载 .env"
else
    echo "   ⚠️  未找到 .env，使用 config.yaml 中的配置"
fi

cd "$SERVER_DIR"

echo ""
echo "📦 编译迁移工具..."
if ! go build -o /tmp/vibe-migrate ./cmd/migrate/; then
    echo "❌ 编译失败"
    exit 1
fi

echo ""
echo "🔄 执行迁移..."
/tmp/vibe-migrate

echo ""
echo "✅ 数据库迁移完成"

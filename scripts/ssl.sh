#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe SSL 证书管理 — Let's Encrypt (certbot) 或自签名
# ============================================================

INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSL_DIR="$INFRA_DIR/ssl"
DOMAIN="${1:-}"

if [ -z "$DOMAIN" ]; then
    echo "用法: $0 <domain>"
    echo "示例: $0 api.example.com"
    echo ""
    echo "如果不需要域名，直接用自签名证书："
    echo "  $0 self-signed"
    exit 1
fi

mkdir -p "$SSL_DIR"

if [ "$DOMAIN" = "self-signed" ]; then
    echo "🔑 生成自签名证书..."
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$SSL_DIR/privkey.pem" \
        -out "$SSL_DIR/fullchain.pem" \
        -subj "/CN=localhost"
    echo "   ✓ 自签名证书已生成 ($SSL_DIR)"
    echo "   ⚠️  浏览器会显示不安全警告"
    exit 0
fi

# Let's Encrypt
echo "🔐 申请 Let's Encrypt 证书: $DOMAIN"

if ! command -v certbot &> /dev/null; then
    echo "❌ certbot 未安装"
    echo "   安装：apt install certbot"
    exit 1
fi

# 先停 Nginx 释放 80 端口
echo "   停止 Nginx..."
docker compose -f "$INFRA_DIR/docker-compose.yml" stop vibe-nginx 2>/dev/null || true

# 申请证书
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"

# 复制证书
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/fullchain.pem"
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$SSL_DIR/privkey.pem"

# 启动 Nginx
echo "   启动 Nginx..."
docker compose -f "$INFRA_DIR/docker-compose.yml" start vibe-nginx 2>/dev/null || true

echo ""
echo "✅ SSL 证书已配置: $DOMAIN"
echo "   续期：certbot renew"

#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Vibe SSL 证书管理 — Let's Encrypt (certbot) 宿主机模式
# 前提：宿主机已安装 nginx 和 certbot
# ============================================================

DOMAIN="${1:-}"
NGINX_CONF_DIR="/etc/nginx/conf.d"

if [ -z "$DOMAIN" ]; then
    echo "用法: $0 <domain>"
    echo "示例: $0 api.vibe.example.com"
    exit 1
fi

echo "🔐 为 $DOMAIN 申请 Let's Encrypt 证书"

# 1. 检查 certbot
if ! command -v certbot &> /dev/null; then
    echo "❌ certbot 未安装"
    echo "   安装：apt install certbot python3-certbot-nginx"
    exit 1
fi

# 2. 确保 Nginx 配置中已有该域名（certbot nginx 插件会自动修改）
NGINX_VIBE_CONF="$NGINX_CONF_DIR/vibe.conf"
if [ ! -f "$NGINX_VIBE_CONF" ]; then
    echo "❌ 未找到 $NGINX_VIBE_CONF"
    echo "   请先运行 deploy.sh 并配置 Nginx"
    exit 1
fi

# 3. 检查配置中的域名是否已替换
if grep -q "YOUR_DOMAIN" "$NGINX_VIBE_CONF"; then
    echo "❌ $NGINX_VIBE_CONF 中仍有 YOUR_DOMAIN 占位符"
    echo "   请先修改为真实域名：sed -i 's/YOUR_DOMAIN/$DOMAIN/g' $NGINX_VIBE_CONF"
    exit 1
fi

# 4. 测试 Nginx 配置
echo "🧪 测试 Nginx 配置..."
if ! nginx -t; then
    echo "❌ Nginx 配置有误，请检查"
    exit 1
fi

# 5. 重载 Nginx 确保 HTTP 验证能通过
echo "🔄 重载 Nginx..."
systemctl reload nginx

# 6. 申请证书（使用 nginx 插件，自动修改 SSL 配置）
echo ""
echo "📋 申请证书..."
certbot --nginx -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    -m "admin@$DOMAIN" \
    --redirect

# 7. 验证
echo ""
echo "🧪 验证 HTTPS..."
if curl -sf "https://$DOMAIN/api/health" > /dev/null 2>&1; then
    echo "   ✅ HTTPS 正常"
else
    echo "   ⚠️  HTTPS 验证失败，请检查 Nginx 配置和证书"
fi

echo ""
echo "✅ SSL 证书已配置: $DOMAIN"
echo "   续期：certbot renew（已自动设置定时任务）"
echo "   续期后重载 Nginx：certbot renew --deploy-hook 'systemctl reload nginx'"

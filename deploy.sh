#!/bin/sh
# One-command production deployment: sh deploy.sh play.example.com
set -eu

cd "$(dirname "$0")"

DOMAIN_VALUE="${1:-${DOMAIN:-}}"
if [ -z "$DOMAIN_VALUE" ]; then
    echo "用法: sh deploy.sh play.example.com" >&2
    exit 1
fi

if [ ! -f .env ]; then
    cp .env.example .env
    sed -i "s/^DOMAIN=.*/DOMAIN=${DOMAIN_VALUE}/" .env
    sed -i "s/^PUBLIC_HOST=.*/PUBLIC_HOST=${DOMAIN_VALUE}/" .env
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "未找到 docker，请先安装 Docker Engine 和 Compose v2" >&2
    exit 1
fi

docker compose up -d --build
docker compose ps
echo
echo "HTTPS: https://${DOMAIN_VALUE}"
echo "健康检查: curl -fsS https://${DOMAIN_VALUE}/healthz"

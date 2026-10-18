#!/bin/sh
# Mode 2: deploy a prebuilt image. Server needs no project source or Godot.
# Usage: sh deploy-image.sh play.example.com ghcr.io/owner/mahjong-online:V1.0.4
set -eu

cd "$(dirname "$0")"

DOMAIN_VALUE="${1:-${DOMAIN:-}}"
IMAGE_VALUE="${2:-${APP_IMAGE:-}}"
if [ -z "$DOMAIN_VALUE" ] || [ -z "$IMAGE_VALUE" ]; then
    echo "用法: sh deploy-image.sh play.example.com ghcr.io/owner/mahjong-online:标签" >&2
    exit 1
fi

if [ ! -f .env ]; then
    cp .env.example .env
fi

if grep -q '^APP_IMAGE=' .env; then
    sed -i "s|^APP_IMAGE=.*|APP_IMAGE=${IMAGE_VALUE}|" .env
else
    printf 'APP_IMAGE=%s\n' "$IMAGE_VALUE" >> .env
fi
sed -i "s|^DOMAIN=.*|DOMAIN=${DOMAIN_VALUE}|" .env
sed -i "s|^PUBLIC_HOST=.*|PUBLIC_HOST=${DOMAIN_VALUE}|" .env

if ! command -v docker >/dev/null 2>&1; then
    echo "未找到 docker，请先安装 Docker Engine 和 Compose v2" >&2
    exit 1
fi

docker compose -f compose.prod.yaml pull
docker compose -f compose.prod.yaml up -d
docker compose -f compose.prod.yaml ps

echo
echo "镜像: ${IMAGE_VALUE}"
echo "HTTPS: https://${DOMAIN_VALUE}"
echo "健康检查: curl -fsS https://${DOMAIN_VALUE}/healthz"

#!/bin/sh
set -eu

: "${PUBLIC_HOST:?set PUBLIC_HOST in .env}"

mkdir -p /app/build/room-server
chown -R mahjong:mahjong /app/build/room-server
chmod 0700 /app/build/room-server

set --
if [ -n "${DOWNLOADS_DIR:-}" ]; then
    set -- "$@" --downloads-dir "${DOWNLOADS_DIR}"
fi
if [ -n "${DOWNLOAD_REDIRECT_PREFIX:-}" ]; then
    set -- "$@" --download-redirect-prefix "${DOWNLOAD_REDIRECT_PREFIX}"
fi

exec gosu mahjong \
    env HOME=/home/mahjong \
    python3 /app/remake/server/room_directory.py \
        --godot /opt/godot/godot \
        --project /app/remake/game \
        --runtime /app/build/room-server \
        --web-dir /app/remake/web \
        --public-host "${PUBLIC_HOST}" \
        --bind 127.0.0.1 \
        --port 8080 \
        --trusted-proxy 127.0.0.1 \
        --first-game-port "${FIRST_PORT:-7600}" \
        --max-rooms "${MAX_ROOMS:-16}" \
        --record-limit "${RECORDS_LIMIT:-100}" "$@"

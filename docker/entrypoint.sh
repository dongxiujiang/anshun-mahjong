#!/bin/sh
set -eu

: "${PUBLIC_HOST:?set PUBLIC_HOST in .env}"

mkdir -p /app/build/room-server
chown -R mahjong:mahjong /app/build/room-server

exec gosu mahjong \
    env HOME=/home/mahjong \
    python3 /app/server/room_directory.py \
        --godot /opt/godot/godot \
        --project /app \
        --public-host "${PUBLIC_HOST}" \
        --bind 0.0.0.0 \
        --http-port 8080 \
        --first-port "${FIRST_PORT:-7600}" \
        --max-rooms "${MAX_ROOMS:-16}"

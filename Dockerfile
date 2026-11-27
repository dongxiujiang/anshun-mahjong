# Mahjong online room server: Python directory + one headless Godot per room.
# Build context is the repository root.
FROM ubuntu:24.04

ARG GODOT_VERSION=4.7.2
ARG GODOT_DOWNLOAD_URL=""

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    HOME=/home/mahjong

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        tini \
        gosu \
        python3 \
        libfontconfig1 \
        libfreetype6 \
        libgl1 \
        libgles2 \
        libegl1 \
        libx11-6 \
        libxcursor1 \
        libxinerama1 \
        libxi6 \
        libxrandr2 \
        libxkbcommon0 \
        libasound2t64 \
        libpulse0 \
        libpipewire-0.3-0t64 \
        libdbus-1-3 \
        libudev1 \
        libzstd1 \
        libpng16-16t64 \
        libjpeg-turbo8 \
        libwebp7 \
        libvorbis0a \
        libogg0 \
        libopus0 \
        libflac12t64 \
        libmpg123-0t64 \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=secret,id=github_token \
    if [ -n "$GODOT_DOWNLOAD_URL" ] && [ -f /run/secrets/github_token ]; then \
        curl --fail --location --retry 5 --retry-all-errors --retry-delay 3 \
            -H "Authorization: Bearer $(cat /run/secrets/github_token)" \
            -H "Accept: application/octet-stream" -o /tmp/godot.zip "$GODOT_DOWNLOAD_URL"; \
    else \
        curl --fail --location --retry 5 --retry-all-errors --retry-delay 3 -o /tmp/godot.zip \
            "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"; \
    fi \
    && unzip -q /tmp/godot.zip -d /opt/godot \
    && mv "/opt/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /opt/godot/godot \
    && chmod 0755 /opt/godot/godot \
    && rm -f /tmp/godot.zip

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin mahjong

WORKDIR /app
COPY --chown=mahjong:mahjong remake/version.json /app/remake/version.json
COPY --chown=mahjong:mahjong remake/game/ /app/remake/game/
COPY --chown=mahjong:mahjong remake/server/ /app/remake/server/
COPY --chown=mahjong:mahjong remake/web/ /app/remake/web/
# Room servers have no microphone and run headless; do not open an input device.
RUN sed -i '/^driver\/enable_input=/d' /app/remake/game/project.godot \
    && gosu mahjong /opt/godot/godot --headless --editor --path /app/remake/game --import

COPY docker/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod 0755 /entrypoint.sh

EXPOSE 7600-7631/udp

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]

# Mahjong online room server: Python directory + one headless Godot per room.
# Build context is the repository root. See server/docker.md.
FROM ubuntu:22.04

ARG GODOT_VERSION=4.7.2

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
        libasound2 \
        libpulse0 \
        libdbus-1-3 \
        libudev1 \
        libzstd1 \
        libpng16-16 \
        libjpeg-turbo8 \
        libwebp7 \
        libvorbis0a \
        libogg0 \
        libopus0 \
        libflac8 \
        libmpg123-0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/godot.zip \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -q /tmp/godot.zip -d /opt/godot \
    && mv "/opt/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /opt/godot/godot \
    && chmod 0755 /opt/godot/godot \
    && rm -f /tmp/godot.zip

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin mahjong

WORKDIR /app
COPY . /app
# The development MCP runtime autoload is only for the editor tooling. It must
# not open a listener inside production room processes.
RUN sed -i '/^MCPRuntimeServer=/d' /app/project.godot
# Room servers have no microphone and run headless; do not open an input device.
RUN sed -i '/^driver\/enable_input=/d' /app/project.godot
# Keep the native extension: the client scripts reference its global classes.
# The headless room server never opens an audio device, but the Linux library
# must still load while the project is imported.
# Bake the import cache into the image so room startup does not race imports.
RUN /opt/godot/godot --headless --editor --path /app --import \
    && chown -R mahjong:mahjong /app

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

EXPOSE 8080/tcp
EXPOSE 7600-7631/udp

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]

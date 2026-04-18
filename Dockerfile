# ================================================================
# hermes-agent-desktop: Linux GUI Desktop + Hermes Agent + Hermes WebUI
# Based on: ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm (KasmVNC)
# ================================================================
#
# Why KasmVNC over Selkies:
#   - Cloud platforms (ModelScope/HuggingFace) only expose a single HTTP port
#   - KasmVNC uses WebSocket VNC — works perfectly behind HTTP reverse proxy
#   - Selkies uses WebRTC — requires independent media streams that cannot
#     penetrate HTTP-only reverse proxies
#   - KasmVNC's built-in Nginx handles HTTP→WebSocket upgrade automatically
#
# Why baseimage-kasmvnc over webtop:
#   - webtop switched to Selkies in June 2025, no KasmVNC variant exists
#   - baseimage-kasmvnc is the official LinuxServer KasmVNC base image
#   - Same s6-overlay init system, same /config persistence model
#   - We install KDE Plasma ourselves (baseimage-kasmvnc ships with Openbox)
#
# Python strategy:
#   Debian 12 Bookworm ships Python 3.11 — compatible with hermes-agent.
#   We create a venv at /opt/hermes-venv using system Python.
#
# WebUI: EKKOLearnAI/hermes-web-ui
#   - Vue 3 + TypeScript + Vite + Naive UI (rich UI)
#   - Koa 2 BFF (Node.js) → proxies to Hermes Gateway API
#   - Features: Web terminal, platform channels, usage analytics, cron jobs
#   - Deployed via: git clone + npm install + npm run build
#   - Runs: node dist/server/index.js (port 8648 → proxies to 8642)
#
# Ports:
#   3000 - KasmVNC desktop (HTTP, default, set CUSTOM_PORT=7860 for cloud)
#   3001 - KasmVNC desktop (HTTPS)
#   8648 - Hermes WebUI (BFF server)
#   8642 - Hermes Agent Gateway API

# ---- Stage 1: Build Hermes WebUI ----
FROM node:22-slim AS webui-builder

WORKDIR /build

# Install build dependencies (git for clone, python3+make+g++ for node-pty native build)
# ca-certificates is required for git clone over HTTPS
RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3 make g++ ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/EKKOLearnAI/hermes-web-ui.git . && \
    rm -rf .git && \
    npm install && \
    npm run build && \
    npm prune --omit=dev && \
    rm -rf /root/.cache /root/.npm

# ---- Stage 2: Final image ----
# Official LinuxServer.io KasmVNC base image (WebSocket VNC, cloud-friendly)
# https://docs.linuxserver.io/images/docker-baseimage-kasmvnc/
FROM ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm

LABEL org.opencontainers.image.source=https://github.com/comedy1024/hermes-agent-desktop
LABEL org.opencontainers.image.description="Hermes Agent + Hermes WebUI in Linux GUI Desktop (KasmVNC)"
LABEL org.opencontainers.image.licenses=MIT

# Install system dependencies + KDE Plasma desktop
# Debian 12 Bookworm: Python 3.11, cmake 3.25 — all compatible with hermes-agent
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc cmake \
    python3 python3-pip python3-venv python3-dev \
    libffi-dev libolm-dev \
    ripgrep ffmpeg procps curl git \
    kde-plasma-desktop konsole kwrite dolphin \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 + npm via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
# pip's resolver fails with "resolution-too-deep" on hermes-agent[all]'s complex
# dependency graph. uv's resolver handles it efficiently (same as official Dockerfile).
# NOTE: baseimage-kasmvnc sets HOME=/config, so uv installs to /config/.local/bin
ENV HOME="/config"
RUN curl -LsSf https://astral.sh/uv/0.6.6/install.sh | sh
ENV PATH="/config/.local/bin:$PATH"

# ---- Clone and install Hermes Agent ----
# Debian 12's Python 3.11 is compatible with hermes-agent.
# We create a venv at /opt/hermes-venv and install hermes-agent[all] into it.
RUN python3 -m venv /opt/hermes-venv && \
    git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes && \
    cd /opt/hermes && \
    uv pip install --python /opt/hermes-venv/bin/python --no-cache -e ".[all]" && \
    npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    cd scripts/whatsapp-bridge && \
    npm install --prefer-offline --no-audit && \
    npm cache clean --force && \
    rm -rf /root/.cache /root/.npm

# Add hermes-venv binaries to PATH so `hermes` CLI works everywhere
ENV PATH="/opt/hermes-venv/bin:$PATH"

# Set up Hermes environment
ENV HERMES_HOME=/config/hermes-data
ENV PYTHONUNBUFFERED=1
RUN mkdir -p /config/hermes-data

# Copy Hermes WebUI from builder stage
COPY --from=webui-builder /build /opt/hermes-webui

# ---- Configure Hermes WebUI environment ----
# EKKOLearnAI/hermes-web-ui is a Node.js BFF (Koa 2) that proxies to
# Hermes Gateway on port 8642. It does NOT need shared Python venv.
# Port: 8648 (BFF) → 8642 (Hermes Gateway)
ENV PORT=8648
ENV UPSTREAM=http://127.0.0.1:8642
ENV HERMES_BIN=/opt/hermes-venv/bin/hermes
ENV HERMES_HOME=/config/hermes-data
ENV NODE_ENV=production

# ---- Copy desktop environment startup script ----
# This replaces the default Openbox with KDE Plasma
COPY root/ /root/

# ---- Install Hermes WebUI as a supervised service ----
# webtop uses s6-overlay for init; we add it to /custom-cont-init.d/ so it starts on each boot
COPY hermes-webui-service.sh /opt/hermes-webui-service.sh
RUN chmod +x /opt/hermes-webui-service.sh

# Register hermes-webui as a background service via custom-cont-init.d
RUN mkdir -p /custom-cont-init.d && \
    printf '#!/bin/bash\n# Start Hermes WebUI in background\nnohup /opt/hermes-webui-service.sh > /config/logs/hermes-webui.log 2>&1 &\n' \
    > /custom-cont-init.d/10-hermes-webui.sh && \
    chmod +x /custom-cont-init.d/10-hermes-webui.sh

# ---- s6-overlay PID 1 compatibility wrapper ----
# Cloud platforms (ModelScope Spaces, HuggingFace Spaces) bypass Docker ENTRYPOINT
# and directly run: /bin/sh -c /init
# This prevents s6-overlay from becoming PID 1, causing fatal error.
#
# Fix: Replace /init with our wrapper that:
#   1. Detects if running as PID 1 (normal Docker) -> exec original s6-overlay
#   2. If not PID 1, tries unshare --pid (requires CAP_SYS_ADMIN)
#   3. If unshare fails (restricted env), falls back to manual service startup
#
# NOTE: With KasmVNC, the cloud fallback is MUCH simpler — KasmVNC's built-in
# Nginx handles HTTP→WebSocket upgrade natively. No custom Nginx config needed.
COPY entrypoint-cloud.sh /entrypoint-cloud.sh
RUN chmod +x /entrypoint-cloud.sh
COPY s6-init.sh /s6-init-wrapper.sh
RUN mv /init /init.s6 && chmod +x /init.s6
RUN mv /s6-init-wrapper.sh /init && chmod +x /init

# Copy our welcome page and wallpaper
COPY welcome.html /opt/welcome.html
COPY wallpaper.png /opt/hermes-wallpaper.png

# ---- Install wallpaper ----
# Strategy: install to MULTIPLE locations so it works regardless of KDE config state:
#   a) Replace the default KDE "Next" theme images (guaranteed to show)
#   b) Install as named wallpaper package for manual selection
#   c) Set system-level default via /etc/xdg/plasmarc
RUN WALLPAPER=/opt/hermes-wallpaper.png && \
    \
    # Location a: replace every image in the KDE default "Next" wallpaper theme
    if [ -d /usr/share/wallpapers/Next ]; then \
        find /usr/share/wallpapers/Next/contents/images -type f \
            \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) | \
            while read img; do cp "$WALLPAPER" "$img"; done; \
    fi && \
    mkdir -p /usr/share/wallpapers/Next/contents/images && \
    cp "$WALLPAPER" /usr/share/wallpapers/Next/contents/images/1920x1080.png && \
    \
    # Location b: named wallpaper package (KDE 5/6 compatible)
    mkdir -p /usr/share/wallpapers/hermes-agent-desktop/contents/images && \
    cp "$WALLPAPER" /usr/share/wallpapers/hermes-agent-desktop/contents/images/1920x1080.png && \
    cp "$WALLPAPER" /usr/share/wallpapers/hermes-agent-desktop/contents/images/1280x800.png && \
    printf '[Desktop Entry]\nName=Hermes Agent Desktop\nX-KDE-PluginInfo-Name=hermes-agent-desktop\nX-KDE-PluginInfo-Author=comedy1024\nX-KDE-PluginInfo-Version=1.0\nX-KDE-PluginInfo-License=MIT\n' \
        > /usr/share/wallpapers/hermes-agent-desktop/metadata.desktop && \
    printf '{"KPlugin":{"Authors":[{"Name":"comedy1024"}],"Id":"hermes-agent-desktop","Name":"Hermes Agent Desktop","License":"MIT","Version":"1.0"}}\n' \
        > /usr/share/wallpapers/hermes-agent-desktop/metadata.json && \
    \
    # Location c: system-level KDE default wallpaper config
    mkdir -p /etc/xdg && \
    printf '[Wallpapers]\ndefaultWallpaper=hermes-agent-desktop\n' > /etc/xdg/plasmarc && \
    \
    echo "[wallpaper] Installed to all KDE wallpaper locations"

# ---- Runtime wallpaper + init script ----
# Called by custom-cont-init.d at every boot to apply wallpaper to live KDE session
RUN printf '#!/bin/bash\n\
# Apply Hermes wallpaper to KDE Plasma at runtime.\n\
WALLPAPER_PATH="file:///usr/share/wallpapers/hermes-agent-desktop/contents/images/1920x1080.png"\n\
PLASMA_RC="/config/.config/plasma-org.kde.plasma.desktop-appletsrc"\n\
\n\
# Method 1: patch appletsrc if it exists\n\
if [ -f "$PLASMA_RC" ]; then\n\
    sed -i "s|^Image=.*|Image=${WALLPAPER_PATH}|g" "$PLASMA_RC"\n\
    sed -i "s|^wallpaperplugin=.*|wallpaperplugin=org.kde.image|g" "$PLASMA_RC"\n\
    echo "[wallpaper] appletsrc patched"\n\
fi\n\
\n\
# Method 2: plasma-apply-wallpaperimage (Plasma 5.23+)\n\
if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then\n\
    DISPLAY=:1 plasma-apply-wallpaperimage \\\n\
        /usr/share/wallpapers/hermes-agent-desktop/contents/images/1920x1080.png \\\n\
        2>/dev/null && echo "[wallpaper] plasma-apply-wallpaperimage done" || true\n\
fi\n\
\n\
# Method 3: kwriteconfig5\n\
if command -v kwriteconfig5 >/dev/null 2>&1; then\n\
    kwriteconfig5 --file plasmarc \\\n\
        --group "Wallpapers" --key "defaultWallpaper" "hermes-agent-desktop" 2>/dev/null || true\n\
fi\n\
\n\
echo "[wallpaper] Apply complete"\n\
' > /opt/apply-wallpaper.sh && chmod +x /opt/apply-wallpaper.sh

# Register wallpaper apply as boot init
RUN printf '#!/bin/bash\n/opt/apply-wallpaper.sh\n' \
    > /custom-cont-init.d/05-apply-wallpaper.sh && \
    chmod +x /custom-cont-init.d/05-apply-wallpaper.sh

# Create Hermes desktop shortcuts
RUN mkdir -p /config/Desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes WebUI\nComment=Hermes Agent Web Interface\nExec=xdg-open http://localhost:8648\nIcon=web-browser\nTerminal=false\nCategories=Network;\n' \
        > /config/Desktop/hermes-webui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=说明文档\nComment=Hermes Agent Desktop 使用帮助\nExec=xdg-open /opt/welcome.html\nIcon=help-about\nTerminal=false\nCategories=Documentation;\n' \
        > /config/Desktop/hermes-welcome.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nComment=Hermes Agent CLI\nExec=konsole --workdir /config/hermes-data -e hermes\nIcon=utilities-terminal\nTerminal=false\nCategories=System;\n' \
        > /config/Desktop/hermes-terminal.desktop && \
    chmod +x /config/Desktop/hermes-*.desktop

# Create KDE autostart entries
RUN mkdir -p /config/.config/autostart && \
    printf '[Desktop Entry]\nType=Application\nName=Open Hermes WebUI\nExec=bash -c "sleep 5 && xdg-open http://localhost:8648"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' \
        > /config/.config/autostart/hermes-webui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Open Welcome Guide\nExec=bash -c "sleep 3 && xdg-open /opt/welcome.html"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' \
        > /config/.config/autostart/hermes-welcome.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nExec=konsole --workdir /config/hermes-data -e hermes\nHidden=false\nX-GNOME-Autostart-enabled=true\n' \
        > /config/.config/autostart/hermes-terminal.desktop

# ---- Bootstrap init script ----
# Runs once at first boot to initialize Hermes Agent config files
RUN printf '#!/bin/bash\n\
# Bootstrap Hermes Agent config (runs once at first boot)\n\
HERMES_HOME="/config/hermes-data"\n\
HERMES_INSTALL="/opt/hermes"\n\
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}\n\
mkdir -p "$HERMES_HOME/.hermes/webui-mvp"\n\
mkdir -p /config/logs\n\
\n\
if [ ! -f "$HERMES_HOME/.env" ] && [ -f "$HERMES_INSTALL/.env.example" ]; then\n\
    cp "$HERMES_INSTALL/.env.example" "$HERMES_HOME/.env"\n\
    echo "[hermes] Created .env from template"\n\
fi\n\
\n\
if [ ! -f "$HERMES_HOME/config.yaml" ] && [ -f "$HERMES_INSTALL/cli-config.yaml.example" ]; then\n\
    cp "$HERMES_INSTALL/cli-config.yaml.example" "$HERMES_HOME/config.yaml"\n\
    echo "[hermes] Created config.yaml from template"\n\
fi\n\
\n\
if [ ! -f "$HERMES_HOME/SOUL.md" ] && [ -f "$HERMES_INSTALL/docker/SOUL.md" ]; then\n\
    cp "$HERMES_INSTALL/docker/SOUL.md" "$HERMES_HOME/SOUL.md"\n\
    echo "[hermes] Created SOUL.md from template"\n\
fi\n\
\n\
if [ -d "$HERMES_INSTALL/skills" ] && [ -f "$HERMES_INSTALL/tools/skills_sync.py" ]; then\n\
    /opt/hermes-venv/bin/python "$HERMES_INSTALL/tools/skills_sync.py" 2>/dev/null || true\n\
fi\n\
\n\
echo "[hermes] Bootstrap complete"\n\
' > /custom-cont-init.d/20-hermes-bootstrap.sh && \
    chmod +x /custom-cont-init.d/20-hermes-bootstrap.sh

# Expose ports
# 3000   - KasmVNC desktop (HTTP, set CUSTOM_PORT=7860 for ModelScope/HuggingFace)
# 3001   - KasmVNC desktop (HTTPS)
# 8648   - Hermes WebUI (BFF server)
# 8642   - Hermes Agent Gateway API
EXPOSE 3000 3001 8648 8642

# Data volume — baseimage-kasmvnc uses /config for all persistent data
VOLUME ["/config"]

# Health check — check KasmVNC on 3000 or WebUI on 8648
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -sf http://localhost:3000/ > /dev/null || curl -sf http://localhost:8648/ > /dev/null || exit 1

# Entrypoint: /init is now our PID 1 wrapper (same path as original s6-overlay init)
# - Normal Docker: detects PID 1, exec's /init.s6 directly (zero overhead)
# - Cloud platforms: detects non-PID-1, falls back to cloud-init mode
#   (KasmVNC's built-in Nginx handles HTTP→WebSocket upgrade natively)
ENTRYPOINT ["/init"]

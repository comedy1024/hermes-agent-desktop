# ================================================================
# hermes-agent-desktop: Hermes Agent + WebUI on Linux KDE Desktop
# Based on: ghcr.io/tunmax/openclaw_computer:latest
# ================================================================
#
# Why openclaw_computer as base:
#   - Proven to work on ModelScope/HuggingFace (same cloud platforms we target)
#   - Debian 12 + KDE + supervisord + TigerVNC + noVNC + websockify
#   - Runs desktop as root (avoids the abc user permission hell we hit with
#     baseimage-kasmvnc: /config not writable, /defaults/ permission denied,
#     XDG_RUNTIME_DIR UID mismatch, KDE "No write access to $HOME", etc.)
#   - Pre-installed: Chrome, fcitx5 Chinese input, zsh
#   - Port 7860 exposed, auto-connect noVNC
#
# Previous baseimage-kasmvnc approach failed because:
#   - Cloud platform overlayFS blocks non-root users from accessing system dirs
#   - abc user (UID=911) couldn't read /defaults/startwm.sh despite 755 perms
#   - KDE refuses to start when HOME (/config) is not writable by the user
#   - chown/chmod on overlayFS doesn't always take effect
#   - After 6+ iterations of permission fixes, the root cause was always the
#     cloud platform's filesystem restrictions on non-root users
#
# Architecture:
#   TigerVNC (:1/5901) → websockify+noVNC (7860) → browser
#   supervisord manages: TigerVNC, noVNC, KDE, hermes-gateway, hermes-webui
#   Everything runs as root (proven approach for cloud platforms)
#
# Ports:
#   7860 - noVNC desktop (HTTP, cloud mode)
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
# Based on openclaw_computer — proven KDE desktop for cloud platforms
FROM ghcr.io/tunmax/openclaw_computer:latest

LABEL org.opencontainers.image.source=https://github.com/comedy1024/hermes-agent-desktop
LABEL org.opencontainers.image.description="Hermes Agent + Hermes WebUI in Linux KDE Desktop (openclaw_computer base)"
LABEL org.opencontainers.image.licenses=MIT

# Install Python venv + build tools for hermes-agent
# openclaw_computer base already has: Python 3, Node.js, Chrome, fcitx5, KDE
# We only need to add: Python dev headers, cmake, libolm for whatsapp bridge,
# and uv for fast pip resolution (pip's resolver fails on hermes-agent[all])
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-dev python3-venv \
    build-essential gcc cmake \
    libffi-dev libolm-dev \
    curl git procps ffmpeg ripgrep && \
    rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
# pip's resolver fails with "resolution-too-deep" on hermes-agent[all]'s complex
# dependency graph. uv's resolver handles it efficiently (same as official Dockerfile).
RUN curl -LsSf https://astral.sh/uv/0.6.6/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

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
ENV HERMES_HOME=/root/hermes-data
ENV PYTHONUNBUFFERED=1
RUN mkdir -p /root/hermes-data

# Copy Hermes WebUI from builder stage
COPY --from=webui-builder /build /opt/hermes-webui

# ---- Configure Hermes WebUI environment ----
# EKKOLearnAI/hermes-web-ui is a Node.js BFF (Koa 2) that proxies to
# Hermes Gateway on port 8642. It does NOT need shared Python venv.
# Port: 8648 (BFF) → 8642 (Hermes Gateway)
ENV PORT=8648
ENV UPSTREAM=http://127.0.0.1:8642
ENV HERMES_BIN=/opt/hermes-venv/bin/hermes
ENV HERMES_HOME=/root/hermes-data
ENV NODE_ENV=production

# ---- Gateway critical settings ----
# API_SERVER_ENABLED=true: enables the HTTP API server platform on port 8642
# Without this, Gateway starts but doesn't listen on any port ("No messaging platforms enabled")
# GATEWAY_ALLOW_ALL_USERS=true: allows all users to access the Gateway
# These can be overridden via docker run -e or .env file
ENV API_SERVER_ENABLED=true
ENV GATEWAY_ALLOW_ALL_USERS=true

# ---- Copy custom configuration ----
# Hermes entrypoint script (bootstrap + start services)
# We don't rely on supervisord conf.d (may not be included in base image's
# supervisord.conf). Instead, hermes-wrapper.sh starts Hermes services
# directly in the background before delegating to the original entrypoint.
COPY hermes-entrypoint.sh /opt/hermes-entrypoint.sh
RUN chmod +x /opt/hermes-entrypoint.sh && sed -i 's/\r$//' /opt/hermes-entrypoint.sh

# Copy welcome page and wallpaper
COPY welcome.html /opt/welcome.html
COPY wallpaper.png /opt/hermes-wallpaper.png

# ---- Install wallpaper ----
RUN WALLPAPER=/opt/hermes-wallpaper.png && \
    if [ -d /usr/share/wallpapers/Next ]; then \
        find /usr/share/wallpapers/Next/contents/images -type f \
            \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) | \
            while read img; do cp "$WALLPAPER" "$img"; done; \
    fi && \
    mkdir -p /usr/share/wallpapers/Next/contents/images && \
    cp "$WALLPAPER" /usr/share/wallpapers/Next/contents/images/1920x1080.png && \
    mkdir -p /usr/share/wallpapers/hermes-agent-desktop/contents/images && \
    cp "$WALLPAPER" /usr/share/wallpapers/hermes-agent-desktop/contents/images/1920x1080.png && \
    cp "$WALLPAPER" /usr/share/wallpapers/hermes-agent-desktop/contents/images/1280x800.png && \
    printf '[Desktop Entry]\nName=Hermes Agent Desktop\nX-KDE-PluginInfo-Name=hermes-agent-desktop\nX-KDE-PluginInfo-Author=comedy1024\nX-KDE-PluginInfo-Version=1.0\nX-KDE-PluginInfo-License=MIT\n' \
        > /usr/share/wallpapers/hermes-agent-desktop/metadata.desktop && \
    printf '{"KPlugin":{"Authors":[{"Name":"comedy1024"}],"Id":"hermes-agent-desktop","Name":"Hermes Agent Desktop","License":"MIT","Version":"1.0"}}\n' \
        > /usr/share/wallpapers/hermes-agent-desktop/metadata.json && \
    echo "[wallpaper] Installed to all KDE wallpaper locations"

# Create Hermes desktop shortcuts
RUN mkdir -p /root/Desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes WebUI\nComment=Hermes Agent Web Interface\nExec=xdg-open http://localhost:8648\nIcon=web-browser\nTerminal=false\nCategories=Network;\n' \
        > /root/Desktop/hermes-webui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=说明文档\nComment=Hermes Agent Desktop 使用帮助\nExec=xdg-open /opt/welcome.html\nIcon=help-about\nTerminal=false\nCategories=Documentation;\n' \
        > /root/Desktop/hermes-welcome.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nComment=Hermes Agent CLI\nExec=konsole --workdir /root/hermes-data -e hermes\nIcon=utilities-terminal\nTerminal=false\nCategories=System;\n' \
        > /root/Desktop/hermes-terminal.desktop && \
    chmod +x /root/Desktop/hermes-*.desktop

# Create KDE autostart entries
RUN mkdir -p /root/.config/autostart && \
    printf '[Desktop Entry]\nType=Application\nName=Open Hermes WebUI\nExec=bash -c "sleep 5 && xdg-open http://localhost:8648"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' \
        > /root/.config/autostart/hermes-webui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nExec=konsole --workdir /root/hermes-data -e hermes\nHidden=false\nX-GNOME-Autostart-enabled=true\n' \
        > /root/.config/autostart/hermes-terminal.desktop

# Expose ports
# 7860 - noVNC desktop (HTTP, cloud mode — already exposed by base image)
# 8648 - Hermes WebUI (BFF server)
# 8642 - Hermes Agent Gateway API
EXPOSE 7860 8648 8642

# Health check — check noVNC on 7860 or WebUI on 8648
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -sf http://localhost:7860/ > /dev/null || curl -sf http://localhost:8648/ > /dev/null || exit 1

# Entrypoint: wrap openclaw_computer's /entrypoint.sh
# We rename the original to /entrypoint-openclaw.sh and install our wrapper
# which runs Hermes bootstrap first, then delegates to the original.
# Hermes services are started by hermes-wrapper.sh as background processes
# with auto-restart loops, then the original entrypoint starts supervisord.
RUN mv /entrypoint.sh /entrypoint-openclaw.sh

COPY hermes-wrapper.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && sed -i 's/\r$//' /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

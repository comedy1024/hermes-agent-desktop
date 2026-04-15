# ================================================================
# hermes-agent-desktop: Linux GUI Desktop + Hermes Agent + Hermes WebUI
# Based on: lscr.io/linuxserver/webtop:ubuntu-kde (official LinuxServer.io)
# ================================================================
#
# Build stages:
#   1. Build Hermes WebUI (Python + vanilla JS, lightweight)
#   2. Combine everything into the official KDE desktop image
#
# Ports:
#   3000 - noVNC web desktop (HTTP)
#   3001 - noVNC web desktop (HTTPS)
#   8787 - Hermes WebUI
#   8642 - Hermes Agent Gateway API

# ---- Stage 1: Build Hermes WebUI ----
FROM python:3.12-slim AS webui-builder

WORKDIR /build

# Clone Hermes WebUI source
RUN apt-get update && apt-get install -y --no-install-recommends git && \
    git clone https://github.com/nesquena/hermes-webui.git . && \
    rm -rf .git

# ---- Stage 2: Final image ----
# Official LinuxServer.io Ubuntu KDE desktop (active maintenance, multi-arch)
# https://docs.linuxserver.io/images/docker-webtop/
FROM lscr.io/linuxserver/webtop:ubuntu-kde

LABEL org.opencontainers.image.source=https://github.com/comedy1024/hermes-agent-desktop
LABEL org.opencontainers.image.description="Hermes Agent + Hermes WebUI in Linux GUI Desktop"
LABEL org.opencontainers.image.licenses=MIT

# Install all system dependencies
# webtop uses apt, we run as root for build-time setup
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc \
    python3 python3-pip python3-venv python3-dev \
    libffi-dev ripgrep ffmpeg procps curl git \
    nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
RUN pip install --no-cache-dir uv --break-system-packages

# Clone and install Hermes Agent (following official Dockerfile approach)
# This is the slowest layer - hermes-agent must be installed into BOTH
# system Python (for CLI `hermes` command) AND the WebUI venv (for deep integration)
RUN git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes && \
    cd /opt/hermes && \
    uv pip install --system --break-system-packages --no-cache -e ".[all]" && \
    npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    cd scripts/whatsapp-bridge && \
    npm install --prefer-offline --no-audit && \
    npm cache clean --force && \
    rm -rf /root/.cache /root/.npm

# Set up Hermes environment
ENV HERMES_HOME=/config/hermes-data
ENV PYTHONUNBUFFERED=1
RUN mkdir -p /config/hermes-data

# Copy Hermes WebUI from builder stage
COPY --from=webui-builder /build /opt/hermes-webui

# ---- Set up Hermes WebUI with shared hermes-agent Python environment ----
# Hermes WebUI deeply integrates with hermes-agent by importing its Python
# modules directly (not via HTTP). It needs hermes-agent in its Python path.
RUN cd /opt/hermes-webui && \
    python3 -m venv venv && \
    venv/bin/pip install --no-cache-dir -r requirements.txt && \
    venv/bin/pip install --no-cache-dir -e "/opt/hermes[all]"

# Configure Hermes WebUI environment
ENV HERMES_WEBUI_AGENT_DIR=/opt/hermes
ENV HERMES_WEBUI_PYTHON=/opt/hermes-webui/venv/bin/python
ENV HERMES_WEBUI_HOST=0.0.0.0
ENV HERMES_WEBUI_PORT=8787
ENV HERMES_WEBUI_STATE_DIR=/config/hermes-data/.hermes/webui-mvp
ENV HERMES_WEBUI_DEFAULT_WORKSPACE=/config/hermes-data
# Touch container marker so WebUI knows it's in Docker
RUN touch /.within_container

# ---- Install Hermes WebUI as a supervised service ----
# webtop uses s6-overlay for init, custom services go in /etc/s6-overlay/s6-rc.d/
# We also add it to /custom-cont-init.d/ so it starts on each boot
COPY hermes-webui-service.sh /opt/hermes-webui-service.sh
RUN chmod +x /opt/hermes-webui-service.sh

# Register hermes-webui as a background service via custom-cont-init.d
RUN mkdir -p /custom-cont-init.d && \
    printf '#!/bin/bash\n# Start Hermes WebUI in background\nnohup /opt/hermes-webui-service.sh > /config/logs/hermes-webui.log 2>&1 &\n' \
    > /custom-cont-init.d/10-hermes-webui.sh && \
    chmod +x /custom-cont-init.d/10-hermes-webui.sh

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
    printf '[Desktop Entry]\nType=Application\nName=Hermes WebUI\nComment=Hermes Agent Web Interface\nExec=xdg-open http://localhost:8787\nIcon=web-browser\nTerminal=false\nCategories=Network;\n' \
        > /config/Desktop/hermes-webui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=说明文档\nComment=Hermes Agent Desktop 使用帮助\nExec=xdg-open /opt/welcome.html\nIcon=help-about\nTerminal=false\nCategories=Documentation;\n' \
        > /config/Desktop/hermes-welcome.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nComment=Hermes Agent CLI\nExec=konsole --workdir /config/hermes-data -e hermes\nIcon=utilities-terminal\nTerminal=false\nCategories=System;\n' \
        > /config/Desktop/hermes-terminal.desktop && \
    chmod +x /config/Desktop/hermes-*.desktop

# Create KDE autostart entries
RUN mkdir -p /config/.config/autostart && \
    printf '[Desktop Entry]\nType=Application\nName=Open Hermes WebUI\nExec=bash -c "sleep 5 && xdg-open http://localhost:8787"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' \
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
    python3 "$HERMES_INSTALL/tools/skills_sync.py" 2>/dev/null || true\n\
fi\n\
\n\
echo "[hermes] Bootstrap complete"\n\
' > /custom-cont-init.d/20-hermes-bootstrap.sh && \
    chmod +x /custom-cont-init.d/20-hermes-bootstrap.sh

# Expose ports
# 3000/3001 - webtop KDE desktop (HTTP/HTTPS)
# 8787      - Hermes WebUI
# 8642      - Hermes Agent Gateway API
EXPOSE 3000 3001 8787 8642

# Data volume — webtop uses /config for all persistent data
VOLUME ["/config"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8787/health || exit 1

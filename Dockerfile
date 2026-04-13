# ================================================================
# hermes-agent-desktop: Linux GUI Desktop + Hermes Agent + Hermes WebUI
# Based on: ghcr.io/tunmax/openclaw_computer (noVNC Linux Desktop)
# ================================================================
#
# Build stages:
#   1. Build Hermes WebUI (Python + vanilla JS, lightweight)
#   2. Combine everything into the openclaw desktop image
#
# Ports:
#   7860 - noVNC web desktop
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
FROM ghcr.io/tunmax/openclaw_computer:latest

LABEL org.opencontainers.image.source=https://github.com/comedy1024/hermes-agent-desktop
LABEL org.opencontainers.image.description="Hermes Agent + Hermes WebUI in Linux GUI Desktop"
LABEL org.opencontainers.image.licenses=MIT

# Install all system dependencies (matching official hermes-agent Dockerfile)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc \
    python3 python3-pip python3-venv python3-dev \
    libffi-dev ripgrep ffmpeg procps supervisor curl \
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

# Copy Hermes Agent docker config templates
# (hermes entrypoint.sh will bootstrap config from these)
RUN chmod +x /opt/hermes/docker/entrypoint.sh

# Set up Hermes environment
ENV HERMES_HOME=/opt/data
ENV PYTHONUNBUFFERED=1
RUN mkdir -p /opt/data

# Copy Hermes WebUI from builder stage
COPY --from=webui-builder /build /opt/hermes-webui

# ---- Set up Hermes WebUI with shared hermes-agent Python environment ----
# Hermes WebUI deeply integrates with hermes-agent by importing its Python
# modules directly (not via HTTP). It needs hermes-agent in its Python path.
# We create a venv for WebUI, install its minimal deps (pyyaml only),
# then install hermes-agent into the same venv so WebUI can import it.
RUN cd /opt/hermes-webui && \
    python3 -m venv venv && \
    venv/bin/pip install --no-cache-dir -r requirements.txt && \
    venv/bin/pip install --no-cache-dir -e "/opt/hermes[all]"

# Configure Hermes WebUI environment
ENV HERMES_WEBUI_AGENT_DIR=/opt/hermes
ENV HERMES_WEBUI_PYTHON=/opt/hermes-webui/venv/bin/python
ENV HERMES_WEBUI_HOST=0.0.0.0
ENV HERMES_WEBUI_PORT=8787
ENV HERMES_WEBUI_STATE_DIR=/opt/data/.hermes/webui-mvp
ENV HERMES_WEBUI_DEFAULT_WORKSPACE=/opt/data
# Touch container marker so WebUI knows it's in Docker
RUN touch /.within_container

# Copy our configuration files
# Rename base image's entrypoint so we can call it from supervisord
RUN mv /entrypoint.sh /opt/openclaw-entrypoint.sh
COPY supervisord.conf /etc/supervisor/conf.d/hermes.conf
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh /opt/openclaw-entrypoint.sh && \
    mkdir -p /var/log/supervisor

# ---- Rebrand from OpenClaw to Hermes Agent Desktop ----
# Copy our welcome page and wallpaper
COPY welcome.html /opt/welcome.html
COPY wallpaper.png /opt/hermes-wallpaper.png
COPY rebrand.sh /tmp/rebrand.sh

# Run comprehensive rebrand
RUN chmod +x /tmp/rebrand.sh && \
    bash /tmp/rebrand.sh && \
    rm -f /tmp/rebrand.sh

# ---- Additional deep scan for remaining brand references ----
# Search noVNC and desktop stack for any remaining "tunmax", "OpenClaw", "b.z" text
RUN echo "[deep-rebrand] Scanning for remaining brand references..." && \
    for f in $(find /usr/share/novnc /opt/noVNC /usr/share/websockify /opt/websockify \
               /usr/share/krfb /usr/share/remote-desktop \
               -type f \( -name '*.html' -o -name '*.js' -o -name '*.css' \) 2>/dev/null); do \
        if grep -qi 'openclaw\|tunmax\|by b\.z\|OpenClaw_Computer\|openclaw_computer' "$f" 2>/dev/null; then \
            echo "[deep-rebrand] Patching brand text in: $f" && \
            sed -i 's/tunmax\/OpenClaw_Computer/comedy1024\/hermes-agent-desktop/gI' "$f" && \
            sed -i 's/tunmax\/openclaw_computer/comedy1024\/hermes-agent-desktop/gI' "$f" && \
            sed -i 's/OpenClaw_Computer/Hermes Agent Desktop/gI' "$f" && \
            sed -i 's/OpenClaw Computer/Hermes Agent Desktop/gI' "$f" && \
            sed -i 's/openclaw_computer/hermes-agent-desktop/gI' "$f" && \
            sed -i 's/by b\.z\./by comedy1024/gI' "$f" && \
            sed -i 's/by b\.z/by comedy1024/gI' "$f" && \
            sed -i 's/tunmax/comedy1024/gI' "$f"; \
        fi; \
    done && \
    for f in $(find / -maxdepth 4 -type f \( -name 'start.sh' -o -name 'start-novnc.sh' \
               -o -name 'entrypoint.sh' -o -name 'novnc*.sh' \) 2>/dev/null \
               | grep -v '/opt/hermes/'); do \
        if grep -qi 'openclaw\|tunmax\|by b\.z' "$f" 2>/dev/null; then \
            echo "[deep-rebrand] Patching brand text in script: $f" && \
            sed -i 's/tunmax\/OpenClaw_Computer/comedy1024\/hermes-agent-desktop/gI' "$f" && \
            sed -i 's/OpenClaw_Computer/Hermes Agent Desktop/gI' "$f" && \
            sed -i 's/OpenClaw Computer/Hermes Agent Desktop/gI' "$f" && \
            sed -i 's/by b\.z/by comedy1024/gI' "$f" && \
            sed -i 's/tunmax/comedy1024/gI' "$f"; \
        fi; \
    done && \
    find / -maxdepth 5 -type f \( -name '*openclaw*logo*' -o -name '*openclaw*icon*' \
       -o -name '*OpenClaw*logo*' -o -name '*OpenClaw*icon*' \) 2>/dev/null | \
        xargs rm -f 2>/dev/null || true && \
    echo "[deep-rebrand] Deep scan complete"

# ---- Apply KDE wallpaper via Plasma config ----
RUN echo "[wallpaper] Setting Hermes wallpaper in KDE Plasma config..." && \
    PLASMA_RC="/root/.config/plasma-org.kde.plasma.desktop-appletsrc" && \
    if [ -f "$PLASMA_RC" ]; then \
        sed -i 's|Image=.*|Image=file:///usr/share/wallpapers/hermes-agent-desktop|g' "$PLASMA_RC"; \
    fi && \
    mkdir -p /usr/share/wallpapers/Next/contents 2>/dev/null && \
    cp -f /opt/hermes-wallpaper.png /usr/share/wallpapers/Next/contents/images.png 2>/dev/null || true && \
    mkdir -p /root/.config && \
    printf '[Wallpaper]\ndefaultWallpaperTheme=hermes-agent-desktop\n' > /root/.config/plasma-wallpaper.conf && \
    echo "[wallpaper] Done"

# Create Hermes desktop shortcuts
RUN printf '[Desktop Entry]\nType=Application\nName=Hermes WebUI\nComment=Hermes Agent Web Interface\nExec=xdg-open http://localhost:8787\nIcon=web-browser\nTerminal=false\nCategories=Network;\n' > /root/Desktop/hermes-webui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=说明文档\nComment=Hermes Agent Desktop 使用帮助\nExec=xdg-open /opt/welcome.html\nIcon=help-about\nTerminal=false\nCategories=Documentation;\n' > /root/Desktop/hermes-welcome.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nComment=Hermes Agent CLI\nExec=konsole --workdir /opt/data -e hermes\nIcon=utilities-terminal\nTerminal=false\nCategories=System;\n' > /root/Desktop/hermes-terminal.desktop && \
    chmod +x /root/Desktop/hermes-*.desktop

# Create KDE autostart entries: open WebUI + Welcome page + Terminal on desktop launch
RUN mkdir -p /root/.config/autostart && \
    printf '[Desktop Entry]\nType=Application\nName=Open Hermes WebUI\nExec=bash -c "sleep 5 && xdg-open http://localhost:8787"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' > /root/.config/autostart/hermes-webui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Open Welcome Guide\nExec=bash -c "sleep 3 && xdg-open /opt/welcome.html"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' > /root/.config/autostart/hermes-welcome.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nExec=konsole --workdir /opt/data -e hermes\nHidden=false\nX-GNOME-Autostart-enabled=true\n' > /root/.config/autostart/hermes-terminal.desktop

# Expose ports
# 7860 - noVNC (from openclaw base)
# 8787 - Hermes WebUI
# 8642 - Hermes Agent Gateway API
EXPOSE 7860 8787 8642

# Data volume
VOLUME ["/opt/data"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8787/health || exit 1

ENTRYPOINT ["/opt/entrypoint.sh"]

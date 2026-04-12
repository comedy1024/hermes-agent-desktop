# ================================================================
# hermes-agent-desktop: Linux GUI Desktop + Hermes Agent + Pan UI (i18n)
# Based on: ghcr.io/tunmax/openclaw_computer (noVNC Linux Desktop)
# ================================================================
#
# Build stages:
#   1. Build Pan UI (Next.js) with Chinese i18n support
#   2. Combine everything into the openclaw desktop image
#
# Ports:
#   7860 - noVNC web desktop
#   3199 - Pan UI web management interface
#   8642 - Hermes Agent Gateway API

# ---- Stage 1: Build Pan UI with i18n ----
FROM node:20-slim AS pan-ui-builder

WORKDIR /build

# Clone Pan UI source
RUN apt-get update && apt-get install -y git && \
    git clone https://github.com/Euraika-Labs/pan-ui.git . && \
    rm -rf .git

# Install dependencies
RUN npm ci

# Install i18n dependency (added by our patches)
RUN npm install next-intl@^4.9.1

# Apply i18n patches - copy over modified files
COPY patches/messages/ ./messages/
COPY patches/i18n/ ./src/i18n/
COPY patches/next.config.ts ./next.config.ts
COPY patches/app/layout.tsx ./src/app/layout.tsx
COPY patches/app/login/ ./src/app/login/
COPY patches/components/ ./src/components/
COPY patches/features/ ./src/features/
COPY patches/lib/ ./src/lib/

# Build Pan UI for production with standalone output
RUN npm run build

# ---- Stage 2: Final image ----
FROM ghcr.io/tunmax/openclaw_computer:latest

LABEL org.opencontainers.image.source=https://github.com/comedy1024/hermes-agent-desktop
LABEL org.opencontainers.image.description="Hermes Agent + Pan UI (i18n) in Linux GUI Desktop"
LABEL org.opencontainers.image.licenses=Apache-2.0

# Install all system dependencies (matching official hermes-agent Dockerfile)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc \
    python3 python3-pip python3-venv python3-dev \
    libffi-dev ripgrep ffmpeg procps supervisor \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
RUN pip install --no-cache-dir uv --break-system-packages

# Clone and install Hermes Agent (following official Dockerfile approach)
# This is the slowest layer - split from Pan UI for better caching
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

# Copy built Pan UI from builder stage
# Note: Pan UI has no public/ directory - static assets are in .next/static
COPY --from=pan-ui-builder /build/.next/standalone /opt/pan-ui
COPY --from=pan-ui-builder /build/.next/static /opt/pan-ui/.next/static
# messages/ contains i18n translation files needed at runtime by next-intl
COPY --from=pan-ui-builder /build/messages /opt/pan-ui/messages

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
# This catches watermarks embedded in HTML/JS/CSS that the base image pre-installs
RUN echo "[deep-rebrand] Scanning for remaining brand references..." && \
    # Search and patch noVNC HTML files for watermark text
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
    # Also patch startup/entrypoint scripts that might inject HTML
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
    # Remove any OpenClaw logo/icon image files
    find / -maxdepth 5 -type f \( -name '*openclaw*logo*' -o -name '*openclaw*icon*' \
       -o -name '*OpenClaw*logo*' -o -name '*OpenClaw*icon*' \) 2>/dev/null | \
        xargs rm -f 2>/dev/null || true && \
    echo "[deep-rebrand] Deep scan complete"

# ---- Apply KDE wallpaper via Plasma config ----
# Read the existing plasma config to find the wallpaper Containment, then patch it
RUN echo "[wallpaper] Setting Hermes wallpaper in KDE Plasma config..." && \
    PLASMA_RC="/root/.config/plasma-org.kde.plasma.desktop-appletsrc" && \
    if [ -f "$PLASMA_RC" ]; then \
        # Replace any existing wallpaper Image= setting with our custom wallpaper
        sed -i 's|Image=.*|Image=file:///usr/share/wallpapers/hermes-agent-desktop|g' "$PLASMA_RC"; \
    fi && \
    # Ensure KDE finds our wallpaper by also symlinking it as default
    mkdir -p /usr/share/wallpapers/Next/contents 2>/dev/null && \
    cp -f /opt/hermes-wallpaper.png /usr/share/wallpapers/Next/contents/images.png 2>/dev/null || true && \
    # Set wallpaper in KDE globals
    mkdir -p /root/.config && \
    printf '[Wallpaper]\ndefaultWallpaperTheme=hermes-agent-desktop\n' > /root/.config/plasma-wallpaper.conf && \
    echo "[wallpaper] Done"

# Create Hermes desktop shortcuts
RUN printf '[Desktop Entry]\nType=Application\nName=Pan UI\nComment=Hermes Agent Web Management Interface\nExec=xdg-open http://localhost:3199\nIcon=web-browser\nTerminal=false\nCategories=Network;\n' > /root/Desktop/hermes-pan-ui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=说明文档\nComment=Hermes Agent Desktop 使用帮助\nExec=xdg-open /opt/welcome.html\nIcon=help-about\nTerminal=false\nCategories=Documentation;\n' > /root/Desktop/hermes-welcome.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nComment=Hermes Agent CLI\nExec=konsole --workdir /opt/data -e hermes\nIcon=utilities-terminal\nTerminal=false\nCategories=System;\n' > /root/Desktop/hermes-terminal.desktop && \
    chmod +x /root/Desktop/hermes-*.desktop

# Create KDE autostart entries: open Pan UI + Welcome page + Terminal on desktop launch
# Pan UI needs a few seconds to start, so we delay browser opening with a small sleep
RUN mkdir -p /root/.config/autostart && \
    printf '[Desktop Entry]\nType=Application\nName=Open Pan UI\nExec=bash -c "sleep 5 && xdg-open http://localhost:3199"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' > /root/.config/autostart/hermes-panui.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Open Welcome Guide\nExec=bash -c "sleep 3 && xdg-open /opt/welcome.html"\nHidden=false\nX-GNOME-Autostart-enabled=true\n' > /root/.config/autostart/hermes-welcome.desktop && \
    printf '[Desktop Entry]\nType=Application\nName=Hermes Terminal\nExec=konsole --workdir /opt/data -e hermes\nHidden=false\nX-GNOME-Autostart-enabled=true\n' > /root/.config/autostart/hermes-terminal.desktop

# Expose ports
# 7860 - noVNC (from openclaw base)
# 3199 - Pan UI
# 8642 - Hermes Gateway API
EXPOSE 7860 3199 8642

# Data volume
VOLUME ["/opt/data"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:3199/ || exit 1

ENTRYPOINT ["/opt/entrypoint.sh"]

#!/bin/bash
# ================================================================
# hermes-entrypoint.sh — Bootstrap Hermes Agent config and services
# ================================================================
# This script runs ONCE at container startup to:
#   1. Initialize Hermes config files (.env, config.yaml, SOUL.md)
#   2. Sync bundled skills
#   3. Create log directories
#   4. Apply wallpaper
#
# Hermes services (gateway + webui) are managed by supervisord,
# not started here. supervisord handles auto-restart and monitoring.
# ================================================================

HERMES_HOME="/root/hermes-data"
HERMES_INSTALL="/opt/hermes"

# Create directory structure
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}
mkdir -p "$HERMES_HOME/.hermes/webui-mvp"

# Copy config templates if they don't exist
if [ ! -f "$HERMES_HOME/.env" ] && [ -f "$HERMES_INSTALL/.env.example" ]; then
    cp "$HERMES_INSTALL/.env.example" "$HERMES_HOME/.env"
    echo "[hermes] Created .env from template"
fi

if [ ! -f "$HERMES_HOME/config.yaml" ] && [ -f "$HERMES_INSTALL/cli-config.yaml.example" ]; then
    cp "$HERMES_INSTALL/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
    echo "[hermes] Created config.yaml from template"
fi

# Ensure critical Gateway settings are enabled in .env
# These are required for the WebUI to connect to the Gateway API.
# We use grep+append (not sed) because the .env may have these lines
# commented out with different comment styles or not present at all.
if ! grep -q "^API_SERVER_ENABLED=" "$HERMES_HOME/.env" 2>/dev/null; then
    echo "" >> "$HERMES_HOME/.env"
    echo "# --- Hermes Agent Desktop: Gateway API Server (auto-configured) ---" >> "$HERMES_HOME/.env"
    echo "API_SERVER_ENABLED=true" >> "$HERMES_HOME/.env"
    echo "[hermes] Added API_SERVER_ENABLED=true to .env"
fi
if ! grep -q "^GATEWAY_ALLOW_ALL_USERS=" "$HERMES_HOME/.env" 2>/dev/null; then
    echo "GATEWAY_ALLOW_ALL_USERS=true" >> "$HERMES_HOME/.env"
    echo "[hermes] Added GATEWAY_ALLOW_ALL_USERS=true to .env"
fi

if [ ! -f "$HERMES_HOME/SOUL.md" ] && [ -f "$HERMES_INSTALL/docker/SOUL.md" ]; then
    cp "$HERMES_INSTALL/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
    echo "[hermes] Created SOUL.md from template"
fi

# Sync bundled skills
if [ -d "$HERMES_INSTALL/skills" ] && [ -f "$HERMES_INSTALL/tools/skills_sync.py" ]; then
    /opt/hermes-venv/bin/python "$HERMES_INSTALL/tools/skills_sync.py" 2>/dev/null || true
fi

# Apply wallpaper (non-critical, best-effort)
if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    DISPLAY=:1 plasma-apply-wallpaperimage \
        /usr/share/wallpapers/hermes-agent-desktop/contents/images/1920x1080.png \
        2>/dev/null || true
fi

# Patch KDE config for wallpaper if it exists
PLASMA_RC="/root/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [ -f "$PLASMA_RC" ]; then
    WALLPAPER_PATH="file:///usr/share/wallpapers/hermes-agent-desktop/contents/images/1920x1080.png"
    sed -i "s|^Image=.*|Image=${WALLPAPER_PATH}|g" "$PLASMA_RC" 2>/dev/null || true
    sed -i "s|^wallpaperplugin=.*|wallpaperplugin=org.kde.image|g" "$PLASMA_RC" 2>/dev/null || true
fi

echo "[hermes] Bootstrap complete"

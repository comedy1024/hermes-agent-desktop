#!/bin/bash
# ================================================================
# hermes-agent-desktop entrypoint
# Starts: noVNC desktop + Hermes Agent Gateway + Pan UI
# All processes managed by supervisord
# ================================================================
set -e

HERMES_HOME="/opt/data"
HERMES_INSTALL="/opt/hermes"

echo "================================================"
echo "  hermes-agent-desktop"
echo "  Hermes Agent + Pan UI (i18n) in Linux GUI"
echo "================================================"

# ---- Bootstrap Hermes Agent config (from official docker/entrypoint.sh) ----
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

# .env
if [ ! -f "$HERMES_HOME/.env" ]; then
    if [ -f "$HERMES_INSTALL/.env.example" ]; then
        cp "$HERMES_INSTALL/.env.example" "$HERMES_HOME/.env"
        echo "[hermes] Created .env from template"
    fi
fi

# config.yaml
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    if [ -f "$HERMES_INSTALL/cli-config.yaml.example" ]; then
        cp "$HERMES_INSTALL/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
        echo "[hermes] Created config.yaml from template"
    fi
fi

# SOUL.md
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    if [ -f "$HERMES_INSTALL/docker/SOUL.md" ]; then
        cp "$HERMES_INSTALL/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
        echo "[hermes] Created SOUL.md from template"
    fi
fi

# Sync bundled skills
if [ -d "$HERMES_INSTALL/skills" ] && [ -f "$HERMES_INSTALL/tools/skills_sync.py" ]; then
    python3 "$HERMES_INSTALL/tools/skills_sync.py" 2>/dev/null || true
fi

echo "================================================"
echo "  Services:"
echo "  - noVNC Desktop:  http://localhost:7860"
echo "  - Pan UI:         http://localhost:3199"
echo "  - Hermes Gateway: http://localhost:8642"
echo "================================================"

# Start supervisord (manages all 3 services)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/hermes.conf

#!/bin/bash
# ================================================================
# hermes-webui-service.sh
# Runs Hermes WebUI as a persistent background service.
# Called from /custom-cont-init.d/10-hermes-webui.sh at every boot.
# Managed by webtop's s6-overlay init system (not supervisord).
# ================================================================

HERMES_HOME="/config/hermes-data"
WEBUI_DIR="/opt/hermes-webui"
LOG_DIR="/config/logs"

mkdir -p "$LOG_DIR"

# Wait for the desktop environment to be ready
sleep 3

echo "[hermes-webui] Starting Hermes WebUI on port 8787..."

exec "$WEBUI_DIR/venv/bin/python" "$WEBUI_DIR/server.py" \
    2>&1 | tee "$LOG_DIR/hermes-webui.log"

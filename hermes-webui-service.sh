#!/bin/bash
# ================================================================
# hermes-webui-service.sh
# Runs EKKOLearnAI/hermes-web-ui as a persistent background service.
# Called from /custom-cont-init.d/10-hermes-webui.sh at every boot.
# Managed by webtop's s6-overlay init system.
# ================================================================
# Architecture:
#   Hermes WebUI (BFF, port 8648) → Hermes Gateway (port 8642)
#   The BFF is a Koa 2 Node.js server that proxies API calls to
#   the Hermes Gateway and serves the Vue 3 frontend.
# ================================================================

HERMES_HOME="/config/hermes-data"
WEBUI_DIR="/opt/hermes-webui"
LOG_DIR="/config/logs"

mkdir -p "$LOG_DIR"

# Wait for the desktop environment to be ready
sleep 3

echo "[hermes-webui] Starting Hermes WebUI on port 8648..."

# Set environment for the BFF server
export PORT=8648
export UPSTREAM=http://127.0.0.1:8642
export HERMES_BIN=/opt/hermes-venv/bin/hermes
export HERMES_HOME="$HERMES_HOME"
export NODE_ENV=production

exec node "$WEBUI_DIR/dist/server/index.js" \
    2>&1 | tee "$LOG_DIR/hermes-webui.log"

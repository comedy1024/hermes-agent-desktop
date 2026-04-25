#!/bin/bash
# ================================================================
# hermes-wrapper.sh — Wrapper for openclaw_computer's /entrypoint.sh
# ================================================================
# This script:
#   1. Runs Hermes Agent bootstrap (config files, skills, wallpaper)
#   2. Starts Hermes Gateway + WebUI as background processes
#   3. Executes the original openclaw_computer /entrypoint.sh
#      which starts supervisord → VNC + KDE + OpenClaw
#
# The original /entrypoint.sh was renamed to /entrypoint-openclaw.sh
# during Dockerfile build to make room for this wrapper.
#
# Hermes services are started here as background processes with a
# simple restart loop (not managed by supervisord, to avoid depending
# on the base image's supervisord configuration).
# ================================================================

echo "[hermes-wrapper] Starting Hermes Agent Desktop..."

# ---- Run Hermes bootstrap ----
/opt/hermes-entrypoint.sh

# ---- Start Hermes Gateway (port 8642) ----
echo "[hermes-wrapper] Starting Hermes Gateway on port 8642..."
export HERMES_HOME=/root/hermes-data
(
    while true; do
        /opt/hermes-venv/bin/hermes gateway run
        RET=$?
        echo "[hermes-wrapper] Hermes Gateway exited (code=$RET), restarting in 5s..."
        sleep 5
    done
) &
GATEWAY_PID=$!
echo "[hermes-wrapper] Hermes Gateway started (PID=$GATEWAY_PID)"

# ---- Start Hermes WebUI (port 8648) ----
echo "[hermes-wrapper] Starting Hermes WebUI on port 8648..."
(
    cd /opt/hermes-webui
    while true; do
        PORT=8648 \
        UPSTREAM=http://127.0.0.1:8642 \
        HERMES_BIN=/opt/hermes-venv/bin/hermes \
        HERMES_HOME=/root/hermes-data \
        AUTH_TOKEN=${AUTH_TOKEN} \
        NODE_ENV=production \
        node dist/server/index.js
        RET=$?
        echo "[hermes-wrapper] Hermes WebUI exited (code=$RET), restarting in 5s..."
        sleep 5
    done
) &
WEBUI_PID=$!
echo "[hermes-wrapper] Hermes WebUI started (PID=$WEBUI_PID)"

# ---- Display WebUI token for user convenience ----
TOKEN_FILE="/root/.hermes-web-ui/.token"
if [ -f "$TOKEN_FILE" ]; then
    CURRENT_TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n')
    echo ""
    echo "=========================================="
    echo "  🔑 WebUI 登录 Token:"
    echo "  $CURRENT_TOKEN"
    echo "=========================================="
    echo "  桌面访问: http://0.0.0.0:7860"
    echo "  Hermes WebUI: http://localhost:8648"
    echo "  Hermes Gateway: http://localhost:8642"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "  Hermes Agent Desktop 已启动！"
    echo "  桌面访问: http://0.0.0.0:7860"
    echo "  Hermes WebUI: http://localhost:8648"
    echo "  Hermes Gateway: http://localhost:8642"
    echo "=========================================="
fi

# ---- Hand off to the original openclaw_computer entrypoint ----
# This starts supervisord which manages: VNC, KDE, OpenClaw, etc.
# supervisord runs in foreground (nodaemon=true) as PID 1.
exec /entrypoint-openclaw.sh

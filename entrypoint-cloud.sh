#!/bin/sh
# ================================================================
# entrypoint-cloud.sh — Cloud platform entrypoint
# ================================================================
# This script is used when s6-overlay cannot run as PID 1
# (e.g., ModelScope/HuggingFace run: /bin/sh -c /init)
#
# Architecture (following openclaw_computer's proven approach):
#   TigerVNC (Xtigervnc) on display :1, port 5901
#   → websockify + noVNC on port 7860
#   → browser accesses desktop via HTTP
#
# This is the classic, reliable VNC-to-web bridge that works
# behind any HTTP reverse proxy (ModelScope, HuggingFace, etc.)
# ================================================================

echo "=========================================="
echo "Hermes Agent Desktop (Cloud Mode)"
echo "=========================================="
echo "[entrypoint-cloud] Starting at $(date)"

# ---- Environment setup ----
export HOME=/config
export USER=abc
export PUID=${PUID:-1000}
export PGID=${PGID:-1000}
export DISPLAY=${DISPLAY:-:1}
export XDG_RUNTIME_DIR=/run/user/${PUID}
export XDG_CONFIG_HOME=/config/.config
export XDG_CACHE_HOME=/config/.cache

# Cloud port — default 7860 for ModelScope/HuggingFace
CLOUD_PORT=${CLOUD_PORT:-7860}

# VNC port (internal, not exposed externally)
VNC_PORT=5901

# Display number derived from DISPLAY
DISPLAY_NUM=$(echo "$DISPLAY" | sed 's/://')

# Resolution
RESOLUTION=${RESOLUTION:-1920x1080}

echo "[entrypoint-cloud] Config: DISPLAY=${DISPLAY} VNC_PORT=${VNC_PORT} CLOUD_PORT=${CLOUD_PORT} RESOLUTION=${RESOLUTION}"

# ---- Ensure required directories exist ----
mkdir -p /config/logs /config/hermes-data /config/.cache /config/.config
mkdir -p /config/.vnc /run /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Clean up stale X11/VNC state (critical for container restarts)
rm -f /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true
pkill -9 -f "Xtigervnc" 2>/dev/null || true
pkill -9 -f "Xvnc" 2>/dev/null || true
pkill -9 -f "websockify" 2>/dev/null || true

# Fix permissions
chown -R abc:abc /config/.cache /config/.config /config/.vnc 2>/dev/null || true
mkdir -p /run/user/${PUID}
chown abc:abc /run/user/${PUID} 2>/dev/null || true

# Fix Fontconfig cache
mkdir -p /config/.cache/fontconfig
chown -R abc:abc /config/.cache/fontconfig 2>/dev/null || true

# Set up user UID/GID
if [ -n "$PUID" ] && [ -n "$PGID" ]; then
    groupmod -o -g "$PGID" abc 2>/dev/null || true
    usermod -o -u "$PUID" abc 2>/dev/null || true
fi

# ---- Run custom init scripts ----
if [ -d /custom-cont-init.d ]; then
    echo "[entrypoint-cloud] Running custom init scripts..."
    for script in /custom-cont-init.d/*.sh; do
        if [ -f "$script" ]; then
            case "$(basename "$script")" in
                *hermes-webui*)
                    echo "[entrypoint-cloud] Skipping: $(basename "$script") (started manually)"
                    continue
                    ;;
            esac
            echo "[entrypoint-cloud] Running: $(basename "$script")"
            chmod +x "$script"
            bash "$script" 2>&1 || true
        fi
    done
fi

# ---- Start D-Bus ----
echo "[entrypoint-cloud] Starting D-Bus..."
if [ -x /usr/bin/dbus-daemon ]; then
    mkdir -p /run/dbus
    dbus-daemon --system --fork 2>/dev/null || true
fi

# ---- Start PulseAudio ----
echo "[entrypoint-cloud] Starting PulseAudio..."
if command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio --start --fail=false --daemonize=true 2>/dev/null || true
fi

# ================================================================
# Start TigerVNC — following openclaw_computer's proven approach
# ================================================================
echo "[entrypoint-cloud] Starting TigerVNC on ${DISPLAY} (${RESOLUTION})..."

# Verify TigerVNC binary exists
if [ ! -x /usr/bin/Xtigervnc ]; then
    echo "[entrypoint-cloud] ERROR: /usr/bin/Xtigervnc not found!"
    echo "[entrypoint-cloud] TigerVNC must be installed in Dockerfile:"
    echo "[entrypoint-cloud]   apt-get install tigervnc-standalone-server"
    echo "[entrypoint-cloud] Available X binaries:"
    ls -la /usr/bin/X* 2>/dev/null || echo "  (none)"
    exit 1
fi

# Create VNC password directory
mkdir -p /config/.vnc
chown abc:abc /config/.vnc 2>/dev/null || true

# Start TigerVNC server
# -SecurityTypes None = no password required (websockify provides the access point)
# -AlwaysShared = allow multiple connections
# -geometry = virtual screen resolution
# This creates a virtual X display on :1 with VNC on port 5901
/usr/bin/Xtigervnc "${DISPLAY}" \
    -geometry "${RESOLUTION}" \
    -depth 24 \
    -SecurityTypes None \
    -AlwaysShared \
    -NeverShared=0 \
    -localhost=0 \
    > /config/logs/vnc.log 2>&1 &

VNC_PID=$!
echo "[entrypoint-cloud] TigerVNC started (PID=$VNC_PID)"

# Wait for VNC server to be ready on port 5901
echo "[entrypoint-cloud] Waiting for VNC server (port ${VNC_PORT})..."
RETRIES=0
while ! ss -tlnp 2>/dev/null | grep -q ":${VNC_PORT} "; do
    sleep 1
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -gt 30 ]; then
        echo "[entrypoint-cloud] ERROR: VNC server failed to start!"
        echo "[entrypoint-cloud] VNC process alive: $(kill -0 $VNC_PID 2>/dev/null && echo 'yes' || echo 'no')"
        echo "[entrypoint-cloud] VNC log (last 30 lines):"
        tail -30 /config/logs/vnc.log 2>/dev/null || echo "(no log)"
        exit 1
    fi
    if [ $((RETRIES % 5)) -eq 0 ]; then
        echo "[entrypoint-cloud] Still waiting... (attempt $RETRIES/30, alive: $(kill -0 $VNC_PID 2>/dev/null && echo 'yes' || echo 'no'))"
    fi
done
echo "[entrypoint-cloud] VNC server is ready on port ${VNC_PORT}."

# ---- Start Desktop Environment (KDE) ----
echo "[entrypoint-cloud] Starting KDE Plasma..."
if [ -f /defaults/startwm.sh ]; then
    cd /config
    DISPLAY="${DISPLAY}" /bin/bash /defaults/startwm.sh &
    DE_PID=$!
else
    echo "[entrypoint-cloud] WARNING: startwm.sh not found, trying startplasma-x11 directly"
    DISPLAY="${DISPLAY}" startplasma-x11 &
    DE_PID=$!
fi
sleep 2

# ================================================================
# Start noVNC + websockify — bridges VNC to WebSocket/HTTP
# ================================================================
echo "[entrypoint-cloud] Starting noVNC on port ${CLOUD_PORT}..."

# Find noVNC web root
NOVNC_WEB=""
if [ -d /usr/share/novnc ]; then
    NOVNC_WEB=/usr/share/novnc
elif [ -d /opt/novnc ]; then
    NOVNC_WEB=/opt/novnc
else
    echo "[entrypoint-cloud] WARNING: noVNC web root not found"
    echo "[entrypoint-cloud] Searched: /usr/share/novnc, /opt/novnc"
fi

# Find websockify binary
WEBSOCKIFY_BIN=""
if [ -x /usr/bin/websockify ]; then
    WEBSOCKIFY_BIN=/usr/bin/websockify
elif command -v websockify >/dev/null 2>&1; then
    WEBSOCKIFY_BIN=$(which websockify)
fi

if [ -z "$WEBSOCKIFY_BIN" ]; then
    echo "[entrypoint-cloud] ERROR: websockify not found!"
    echo "[entrypoint-cloud] Install with: apt-get install websockify"
    exit 1
fi

echo "[entrypoint-cloud] Using websockify: ${WEBSOCKIFY_BIN}"
if [ -n "$NOVNC_WEB" ]; then
    echo "[entrypoint-cloud] noVNC web root: ${NOVNC_WEB}"
    "${WEBSOCKIFY_BIN}" \
        --web "${NOVNC_WEB}" \
        0.0.0.0:${CLOUD_PORT} \
        localhost:${VNC_PORT} \
        > /config/logs/novnc.log 2>&1 &
else
    "${WEBSOCKIFY_BIN}" \
        0.0.0.0:${CLOUD_PORT} \
        localhost:${VNC_PORT} \
        > /config/logs/novnc.log 2>&1 &
fi

NOVNC_PID=$!
echo "[entrypoint-cloud] noVNC started (PID=$NOVNC_PID)"

# Wait for noVNC to be ready
RETRIES=0
while ! ss -tlnp 2>/dev/null | grep -q ":${CLOUD_PORT} "; do
    sleep 1
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -gt 15 ]; then
        echo "[entrypoint-cloud] ERROR: noVNC failed to start!"
        echo "[entrypoint-cloud] noVNC log (last 20 lines):"
        tail -20 /config/logs/novnc.log 2>/dev/null || echo "(no log)"
        exit 1
    fi
done
echo "[entrypoint-cloud] noVNC is ready on port ${CLOUD_PORT}."

# ---- Start Hermes Gateway (port 8642) ----
echo "[entrypoint-cloud] Starting Hermes Gateway on port 8642..."
export HERMES_HOME=/config/hermes-data
if [ -x /opt/hermes-venv/bin/hermes ]; then
    /opt/hermes-venv/bin/hermes gateway run &
    GATEWAY_PID=$!
    echo "[entrypoint-cloud] Hermes Gateway started (PID=$GATEWAY_PID)"
else
    echo "[entrypoint-cloud] WARNING: hermes CLI not found, skipping gateway"
    GATEWAY_PID=""
fi

# ---- Start Hermes WebUI (localhost only) ----
echo "[entrypoint-cloud] Starting Hermes WebUI on port 8648..."
if [ -f /opt/hermes-webui-service.sh ]; then
    bash /opt/hermes-webui-service.sh &
    WEBUI_PID=$!
else
    cd /opt/hermes-webui
    PORT=8648 UPSTREAM=http://127.0.0.1:8642 \
        HERMES_BIN=/opt/hermes-venv/bin/hermes \
        HERMES_HOME=/config/hermes-data \
        NODE_ENV=production \
        node dist/server/index.js &
    WEBUI_PID=$!
fi

echo ""
echo "=========================================="
echo "  KDE Plasma 桌面已启动！"
echo "  访问地址: http://0.0.0.0:${CLOUD_PORT}"
echo "  分辨率:   ${RESOLUTION}"
echo "  Hermes WebUI: http://localhost:8648"
echo "  Hermes Gateway: http://localhost:8642"
echo "=========================================="

# ---- Keep container alive and monitor services ----
while true; do
    sleep 30

    # Check VNC server
    if ! kill -0 $VNC_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: VNC server died, restarting..."
        rm -f /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true
        /usr/bin/Xtigervnc "${DISPLAY}" \
            -geometry "${RESOLUTION}" -depth 24 \
            -SecurityTypes None -AlwaysShared \
            > /config/logs/vnc.log 2>&1 &
        VNC_PID=$!
    fi

    # Check noVNC
    if ! kill -0 $NOVNC_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: noVNC died, restarting..."
        if [ -n "$NOVNC_WEB" ]; then
            "${WEBSOCKIFY_BIN}" --web "${NOVNC_WEB}" \
                0.0.0.0:${CLOUD_PORT} localhost:${VNC_PORT} \
                > /config/logs/novnc.log 2>&1 &
        else
            "${WEBSOCKIFY_BIN}" \
                0.0.0.0:${CLOUD_PORT} localhost:${VNC_PORT} \
                > /config/logs/novnc.log 2>&1 &
        fi
        NOVNC_PID=$!
    fi

    # Check Hermes Gateway
    if [ -n "$GATEWAY_PID" ] && ! kill -0 $GATEWAY_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: Hermes Gateway died, restarting..."
        /opt/hermes-venv/bin/hermes gateway run &
        GATEWAY_PID=$!
    fi

    # Check WebUI
    if [ -n "$WEBUI_PID" ] && ! kill -0 $WEBUI_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: Hermes WebUI died, restarting..."
        if [ -f /opt/hermes-webui-service.sh ]; then
            bash /opt/hermes-webui-service.sh &
        else
            cd /opt/hermes-webui
            PORT=8648 UPSTREAM=http://127.0.0.1:8642 \
                HERMES_BIN=/opt/hermes-venv/bin/hermes \
                HERMES_HOME=/config/hermes-data \
                NODE_ENV=production \
                node dist/server/index.js &
        fi
        WEBUI_PID=$!
    fi
done

#!/bin/bash
# ================================================================
# entrypoint-cloud.sh — Cloud platform entrypoint (KasmVNC edition)
# ================================================================
# This script is used when s6-overlay cannot run as PID 1
# (e.g., ModelScope/HuggingFace run: /bin/sh -c /init)
#
# Architecture (KasmVNC — single port, cloud-friendly):
#   Browser → KasmVNC (HTTP + WebSocket on same port)
#   No separate Nginx needed — KasmVNC handles everything!
#
# Key difference from old Selkies version:
#   Selkies needed: Browser → Nginx(7860) → Selkies WebRTC(8082)
#   KasmVNC needs:  Browser → KasmVNC(7860) — done!
# ================================================================

echo "=========================================="
echo "Hermes Agent Desktop (Cloud Mode — KasmVNC)"
echo "=========================================="
echo "[entrypoint-cloud] Starting at $(date)"
echo "[entrypoint-cloud] Script version: kasmvnc-1"

# ---- Environment setup ----
export HOME=/config
export USER=abc
export PUID=${PUID:-1000}
export PGID=${PGID:-1000}
export DISPLAY=${DISPLAY:-:1}
export XDG_RUNTIME_DIR=/run/user/${PUID}

# Cloud port — default 7860 for ModelScope/HuggingFace
CLOUD_PORT=${CLOUD_PORT:-7860}

# Ensure required directories exist
mkdir -p /config/logs /config/hermes-data /config/.cache /config/.config
mkdir -p /run /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
rm -rf /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true

# Fix permissions
chown -R abc:abc /config/.cache 2>/dev/null || true
chown -R abc:abc /config/.config 2>/dev/null || true
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
            if [[ "$(basename "$script")" == *"hermes-webui"* ]]; then
                echo "[entrypoint-cloud] Skipping: $(basename "$script") (started manually)"
                continue
            fi
            echo "[entrypoint-cloud] Running: $(basename "$script")"
            chmod +x "$script"
            bash "$script" 2>&1 || true
        fi
    done
fi

# ---- Start Xvfb ----
echo "[entrypoint-cloud] Starting Xvfb..."
rm -f /tmp/.X1-lock

VFBCOMMAND=""
if ! which nvidia-smi 2>/dev/null && [ -e "/dev/dri/renderD128" ]; then
    VFBCOMMAND="-vfbdevice /dev/dri/renderD128"
fi
if [ -n "${DRINODE}" ]; then
    VFBCOMMAND="-vfbdevice ${DRINODE}"
fi

DEFAULT_RES="1280x720x24"
if [ -n "${SELKIES_MANUAL_WIDTH}" ] || [ -n "${SELKIES_MANUAL_HEIGHT}" ]; then
    T_WIDTH="${SELKIES_MANUAL_WIDTH:-1280}"
    T_HEIGHT="${SELKIES_MANUAL_HEIGHT:-720}"
    [ "${T_WIDTH}" = "0" ] && T_WIDTH=1280
    [ "${T_HEIGHT}" = "0" ] && T_HEIGHT=720
    DEFAULT_RES="${T_WIDTH}x${T_HEIGHT}x24"
fi

s6-setuidgid abc /usr/bin/Xvfb \
    "${DISPLAY}" \
    -screen 0 "${DEFAULT_RES}" \
    -dpi 96 \
    +extension COMPOSITE +extension DAMAGE +extension GLX \
    +extension RANDR +extension RENDER +extension MIT-SHM \
    +extension XFIXES +extension XTEST \
    +iglx +render \
    -nolisten tcp -ac -noreset -shmem \
    ${VFBCOMMAND} &
XVFB_PID=$!

# Wait for X
echo "[entrypoint-cloud] Waiting for X server..."
RETRIES=0
while ! xset q &>/dev/null; do
    sleep 0.5
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -gt 30 ]; then
        echo "[entrypoint-cloud] ERROR: X server failed to start!"
        exit 1
    fi
done
echo "[entrypoint-cloud] X server is ready."

# ---- Start D-Bus ----
echo "[entrypoint-cloud] Starting D-Bus..."
if [ -x /usr/bin/dbus-daemon ]; then
    mkdir -p /run/dbus
    dbus-daemon --system --fork 2>/dev/null || true
fi

# ---- Start PulseAudio ----
echo "[entrypoint-cloud] Starting PulseAudio..."
if command -v pulseaudio >/dev/null 2>&1; then
    s6-setuidgid abc pulseaudio --start --fail=false \
        --daemonize=true 2>/dev/null || true
fi

# ---- Start Desktop Environment (KDE) ----
echo "[entrypoint-cloud] Starting KDE Plasma..."
if [ -f /defaults/startwm.sh ]; then
    cd /config
    s6-setuidgid abc /bin/bash /defaults/startwm.sh &
    DE_PID=$!
elif [ -f /root/defaults/startwm.sh ]; then
    cd /config
    s6-setuidgid abc /bin/bash /root/defaults/startwm.sh &
    DE_PID=$!
else
    echo "[entrypoint-cloud] WARNING: startwm.sh not found, trying startplasma-x11 directly"
    s6-setuidgid abc startplasma-x11 &
    DE_PID=$!
fi
sleep 2

# ---- Start KasmVNC ----
# KasmVNC is the key: it provides both HTTP and WebSocket on the SAME port.
# No Nginx needed — it handles browser connections directly.
echo "[entrypoint-cloud] Starting KasmVNC on port ${CLOUD_PORT}..."

# Generate KasmVNC config
mkdir -p /config/.vnc
cat > /config/.vnc/kasmvnc.yaml << 'KASMVNCCONF'
network:
  protocol: http
  websocket:
    port: 0
  ssl:
    require_ssl: false
desktop:
  allow_resize: true
  pixel_buffer: true
encoding:
  max_frame_rate: 30
  prefer_remote_encoding: true
security:
  brute_force_protection:
    blacklist_threshold: 5
    blacklist_timeout: 10
KASMVNCCONF

# Set KasmVNC port via environment
export KASM_PORT=${CLOUD_PORT}
export VNC_PORT=${CLOUD_PORT}

if command -v vncserver >/dev/null 2>&1; then
    # KasmVNC's vncserver handles HTTP + WebSocket on the same port
    s6-setuidgid abc vncserver :1 -geometry 1280x720 -depth 24 \
        -websocketPort ${CLOUD_PORT} \
        -httpPort ${CLOUD_PORT} \
        -interface 0.0.0.0 \
        2>&1 || {
        echo "[entrypoint-cloud] WARNING: vncserver failed, trying alternative..."
        # Alternative: try kasmvncserver
        if command -v kasmvncserver >/dev/null 2>&1; then
            s6-setuidgid abc kasmvncserver :1 -geometry 1280x720 -depth 24 \
                -websocketPort ${CLOUD_PORT} \
                -interface 0.0.0.0 2>&1 || true
        fi
    }
    echo "[entrypoint-cloud] KasmVNC started on port ${CLOUD_PORT}"
else
    echo "[entrypoint-cloud] WARNING: vncserver not found!"
    echo "[entrypoint-cloud] Checking for KasmVNC binary..."
    ls -la /usr/bin/vnc* /usr/bin/kasm* /opt/kasmvnc/bin/ 2>/dev/null || true
fi

# ---- Start Hermes Gateway (port 8642) ----
echo "[entrypoint-cloud] Starting Hermes Gateway on port 8642..."
export HERMES_HOME=/config/hermes-data
if [ -x /opt/hermes-venv/bin/hermes ]; then
    s6-setuidgid abc /opt/hermes-venv/bin/hermes gateway run &
    GATEWAY_PID=$!
    echo "[entrypoint-cloud] Hermes Gateway started (PID=$GATEWAY_PID)"
else
    echo "[entrypoint-cloud] WARNING: hermes CLI not found, skipping gateway"
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

echo "=========================================="
echo "All services started!"
echo "- KasmVNC Desktop:  http://0.0.0.0:${CLOUD_PORT}"
echo "- Hermes WebUI:     http://localhost:8648"
echo "- Hermes Gateway:   http://localhost:8642"
echo "=========================================="

# ---- Keep container alive and monitor services ----
while true; do
    sleep 30

    # Check Xvfb
    if ! kill -0 $XVFB_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: Xvfb died, restarting..."
        rm -f /tmp/.X1-lock
        s6-setuidgid abc /usr/bin/Xvfb "${DISPLAY}" \
            -screen 0 "${DEFAULT_RES}" -dpi 96 \
            +extension COMPOSITE +extension DAMAGE +extension GLX \
            +extension RANDR +extension RENDER +extension MIT-SHM \
            +extension XFIXES +extension XTEST \
            +iglx +render -nolisten tcp -ac -noreset -shmem \
            ${VFBCOMMAND} &
        XVFB_PID=$!
    fi

    # Check Hermes Gateway
    if [ -n "$GATEWAY_PID" ] && ! kill -0 $GATEWAY_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: Hermes Gateway died, restarting..."
        s6-setuidgid abc /opt/hermes-venv/bin/hermes gateway run &
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

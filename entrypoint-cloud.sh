#!/bin/sh
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
echo "[entrypoint-cloud] Script version: kasmvnc-2"

# ---- Environment setup ----
export HOME=/config
export USER=abc
export PUID=${PUID:-1000}
export PGID=${PGID:-1000}
export DISPLAY=${DISPLAY:-:1}
export XDG_RUNTIME_DIR=/run/user/${PUID}

# Cloud port — default 7860 for ModelScope/HuggingFace
CLOUD_PORT=${CLOUD_PORT:-7860}

# ---- Helper: run command as user 'abc' ----
# In cloud mode, s6-overlay is NOT running, so s6-setuidgid may not be in PATH.
# We define a helper that tries multiple methods:
#   1. /command/s6-setuidgid (s6-overlay installed but not in PATH)
#   2. s6-setuidgid (in PATH — s6-overlay set it up)
#   3. runuser -u abc (PAM-based, available on Debian)
#   4. su - abc -c (fallback)
run_as_abc() {
    if command -v /command/s6-setuidgid >/dev/null 2>&1; then
        /command/s6-setuidgid abc "$@"
    elif command -v s6-setuidgid >/dev/null 2>&1; then
        s6-setuidgid abc "$@"
    elif command -v runuser >/dev/null 2>&1; then
        runuser -u abc -- "$@"
    else
        su - abc -c "$*"
    fi
}

echo "[entrypoint-cloud] User switching method: $(which /command/s6-setuidgid 2>/dev/null || which s6-setuidgid 2>/dev/null || which runuser 2>/dev/null || echo 'su')"

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

# ---- Start Xvfb ----
echo "[entrypoint-cloud] Starting Xvfb on display ${DISPLAY}..."
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

# Start Xvfb — capture output for debugging
XVFB_LOG=/config/logs/xvfb.log
run_as_abc /usr/bin/Xvfb \
    "${DISPLAY}" \
    -screen 0 "${DEFAULT_RES}" \
    -dpi 96 \
    +extension COMPOSITE +extension DAMAGE +extension GLX \
    +extension RANDR +extension RENDER +extension MIT-SHM \
    +extension XFIXES +extension XTEST \
    +iglx +render \
    -nolisten tcp -ac -noreset -shmem \
    ${VFBCOMMAND} > "$XVFB_LOG" 2>&1 &
XVFB_PID=$!
echo "[entrypoint-cloud] Xvfb started (PID=$XVFB_PID)"

# Give Xvfb a moment to start (or fail)
sleep 1

# Check if Xvfb process is still alive
if ! kill -0 $XVFB_PID 2>/dev/null; then
    echo "[entrypoint-cloud] ERROR: Xvfb process died immediately!"
    echo "[entrypoint-cloud] Xvfb log:"
    cat "$XVFB_LOG" 2>/dev/null
    echo "[entrypoint-cloud] Trying Xvfb as root instead..."
    /usr/bin/Xvfb \
        "${DISPLAY}" \
        -screen 0 "${DEFAULT_RES}" \
        -dpi 96 \
        +extension COMPOSITE +extension DAMAGE +extension GLX \
        +extension RANDR +extension RENDER +extension MIT-SHM \
        +extension XFIXES +extension XTEST \
        +iglx +render \
        -nolisten tcp -ac -noreset -shmem \
        ${VFBCOMMAND} > "$XVFB_LOG" 2>&1 &
    XVFB_PID=$!
    sleep 1
fi

# Wait for X
echo "[entrypoint-cloud] Waiting for X server..."
RETRIES=0
while ! xset q &>/dev/null; do
    sleep 0.5
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -gt 30 ]; then
        echo "[entrypoint-cloud] ERROR: X server failed to start!"
        echo "[entrypoint-cloud] Xvfb process alive: $(kill -0 $XVFB_PID 2>/dev/null && echo 'yes' || echo 'no')"
        echo "[entrypoint-cloud] Xvfb log (last 20 lines):"
        tail -20 "$XVFB_LOG" 2>/dev/null || echo "(no log)"
        echo "[entrypoint-cloud] X lock files:"
        ls -la /tmp/.X*-lock /tmp/.X11-unix/ 2>/dev/null || echo "(none)"
        echo "[entrypoint-cloud] User info:"
        id abc 2>/dev/null || echo "user abc not found"
        exit 1
    fi
    # Log progress every 5 retries
    if [ $((RETRIES % 5)) -eq 0 ]; then
        echo "[entrypoint-cloud] Still waiting for X... (attempt $RETRIES/30, Xvfb alive: $(kill -0 $XVFB_PID 2>/dev/null && echo 'yes' || echo 'no'))"
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
    run_as_abc pulseaudio --start --fail=false \
        --daemonize=true 2>/dev/null || true
fi

# ---- Start Desktop Environment (KDE) ----
echo "[entrypoint-cloud] Starting KDE Plasma..."
if [ -f /defaults/startwm.sh ]; then
    cd /config
    run_as_abc /bin/bash /defaults/startwm.sh &
    DE_PID=$!
elif [ -f /root/defaults/startwm.sh ]; then
    cd /config
    run_as_abc /bin/bash /root/defaults/startwm.sh &
    DE_PID=$!
else
    echo "[entrypoint-cloud] WARNING: startwm.sh not found, trying startplasma-x11 directly"
    run_as_abc startplasma-x11 &
    DE_PID=$!
fi
sleep 2

# ---- Start KasmVNC ----
# KasmVNC is the key: it provides both HTTP and WebSocket on the SAME port.
# No Nginx needed — it handles browser connections directly.
echo "[entrypoint-cloud] Starting KasmVNC on port ${CLOUD_PORT}..."

# Generate KasmVNC config
mkdir -p /config/.vnc
cat > /config/.vnc/kasmvnc.yaml << KASMVNCCONF
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

# Set KasmVNC password (required for vncserver)
mkdir -p /config/.vnc
if [ ! -f /config/.vnc/passwd ]; then
    echo "[entrypoint-cloud] Setting VNC password..."
    # Set a default password (abc123) — user can change it via VNC settings
    echo "abc123" | vncpasswd -f > /config/.vnc/passwd 2>/dev/null || true
    chmod 600 /config/.vnc/passwd 2>/dev/null || true
    chown abc:abc /config/.vnc/passwd 2>/dev/null || true
fi

# Set KasmVNC port via environment
export KASM_PORT=${CLOUD_PORT}
export VNC_PORT=${CLOUD_PORT}

# Find KasmVNC binaries
VNC_BIN=""
for bin in /usr/bin/vncserver /usr/local/bin/vncserver /opt/kasmvnc/bin/vncserver; do
    if [ -x "$bin" ]; then
        VNC_BIN="$bin"
        break
    fi
done

if [ -n "$VNC_BIN" ]; then
    echo "[entrypoint-cloud] Using KasmVNC at: $VNC_BIN"
    # KasmVNC's vncserver handles HTTP + WebSocket on the same port
    run_as_abc "$VNC_BIN" :1 -geometry 1280x720 -depth 24 \
        -websocketPort ${CLOUD_PORT} \
        -httpPort ${CLOUD_PORT} \
        -interface 0.0.0.0 \
        2>&1 || {
        echo "[entrypoint-cloud] WARNING: vncserver failed, trying without port flags..."
        # Some KasmVNC versions use different flag names
        run_as_abc "$VNC_BIN" :1 -geometry 1280x720 -depth 24 \
            -interface 0.0.0.0 2>&1 || {
            echo "[entrypoint-cloud] WARNING: All vncserver attempts failed"
            echo "[entrypoint-cloud] Trying to start kasmvnc directly..."
            if [ -x /opt/kasmvnc/bin/kasmvnc ]; then
                /opt/kasmvnc/bin/kasmvnc :1 -geometry 1280x720 -depth 24 2>&1 || true
            fi
        }
    }
    echo "[entrypoint-cloud] KasmVNC started on port ${CLOUD_PORT}"
else
    echo "[entrypoint-cloud] WARNING: vncserver not found!"
    echo "[entrypoint-cloud] Checking for KasmVNC binary..."
    ls -la /usr/bin/vnc* /usr/local/bin/vnc* /opt/kasmvnc/bin/ 2>/dev/null || true
    echo "[entrypoint-cloud] Attempting manual KasmVNC start..."
    # Try the kasmvnc binary directly
    for bin in /opt/kasmvnc/bin/kasmvnc /usr/bin/kasmvnc; do
        if [ -x "$bin" ]; then
            run_as_abc "$bin" :1 -geometry 1280x720 -depth 24 2>&1 || true
            break
        fi
    done
fi

# ---- Start Hermes Gateway (port 8642) ----
echo "[entrypoint-cloud] Starting Hermes Gateway on port 8642..."
export HERMES_HOME=/config/hermes-data
if [ -x /opt/hermes-venv/bin/hermes ]; then
    run_as_abc /opt/hermes-venv/bin/hermes gateway run &
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
        run_as_abc /usr/bin/Xvfb "${DISPLAY}" \
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
        run_as_abc /opt/hermes-venv/bin/hermes gateway run &
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

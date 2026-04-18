#!/bin/sh
# ================================================================
# entrypoint-cloud.sh — Cloud platform entrypoint (KasmVNC edition)
# ================================================================
# This script is used when s6-overlay cannot run as PID 1
# (e.g., ModelScope/HuggingFace run: /bin/sh -c /init)
#
# Architecture:
#   Browser → NGINX(7860) → KasmVNC Xvnc + Kclient
#   KasmVNC's Xvnc integrates Xvfb + VNC — no separate Xvfb needed!
#
# Reference: linuxserver/baseimage-kasmvnc s6 service scripts
#   - svc-kasmvnc/run: /usr/local/bin/Xvnc
#   - svc-nginx/run: /usr/sbin/nginx
#   - svc-kclient/run: /kclient/node index.js
# ================================================================

echo "=========================================="
echo "Hermes Agent Desktop (Cloud Mode — KasmVNC)"
echo "=========================================="
echo "[entrypoint-cloud] Starting at $(date)"
echo "[entrypoint-cloud] Script version: kasmvnc-3"

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

# ---- Ensure required directories exist ----
mkdir -p /config/logs /config/hermes-data /config/.cache /config/.config
mkdir -p /config/.vnc /run /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Clean up stale X11/VNC state (critical for container restarts)
rm -f /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true
pkill -9 -f "Xvnc" 2>/dev/null || true
pkill -9 -f "Xvfb" 2>/dev/null || true

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
    run_as_abc pulseaudio --start --fail=false \
        --daemonize=true 2>/dev/null || true
fi

# ---- Start KasmVNC (Xvnc) ----
# This is the KEY insight from linuxserver/baseimage-kasmvnc:
# KasmVNC's Xvnc integrates Xvfb + VNC server. No separate Xvfb needed!
echo "[entrypoint-cloud] Starting KasmVNC (Xvnc) on display ${DISPLAY}..."

# GPU hardware acceleration detection (from linuxserver s6 svc-kasmvnc/run)
HW3D=""
if ls /dev/dri/renderD* 1>/dev/null 2>&1 && [ -z "${DISABLE_DRI+x}" ] && ! which nvidia-smi 2>/dev/null; then
    HW3D="-hw3d"
    echo "[entrypoint-cloud] GPU 3D acceleration enabled"
fi

DRINODE=${DRINODE:-/dev/dri/renderD128}

# Resolution settings
RESOLUTION=${RESOLUTION:-1280x720}

# Start Xvnc — this replaces the old Xvfb + vncserver two-step approach
# Reference: linuxserver baseimage-kasmvnc svc-kasmvnc/run
if [ -x /usr/local/bin/Xvnc ]; then
    echo "[entrypoint-cloud] Using /usr/local/bin/Xvnc"
    run_as_abc /usr/local/bin/Xvnc "${DISPLAY}" \
        ${HW3D} \
        -PublicIP 127.0.0.1 \
        -drinode "${DRINODE}" \
        -disableBasicAuth \
        -SecurityTypes None \
        -AlwaysShared \
        -geometry "${RESOLUTION}" \
        -sslOnly 0 \
        -RectThreads 0 \
        -websocketPort "${CLOUD_PORT}" \
        -httpPort "${CLOUD_PORT}" \
        -interface 0.0.0.0 \
        -Log *:stdout:100 \
        > /config/logs/kasmvnc.log 2>&1 &
    KASMVNC_PID=$!
elif [ -x /usr/bin/vncserver ]; then
    echo "[entrypoint-cloud] Using /usr/bin/vncserver"
    # Fallback: use vncserver if Xvnc is not available
    run_as_abc /usr/bin/vncserver "${DISPLAY}" \
        -geometry "${RESOLUTION}" \
        -depth 24 \
        -websocketPort "${CLOUD_PORT}" \
        -httpPort "${CLOUD_PORT}" \
        -interface 0.0.0.0 \
        -sslOnly 0 \
        -SecurityTypes None \
        -disableBasicAuth \
        -AlwaysShared \
        > /config/logs/kasmvnc.log 2>&1 &
    KASMVNC_PID=$!
else
    echo "[entrypoint-cloud] ERROR: No KasmVNC binary found!"
    echo "[entrypoint-cloud] Searched: /usr/local/bin/Xvnc, /usr/bin/vncserver"
    ls -la /usr/local/bin/X* /usr/bin/vnc* /usr/bin/X* 2>/dev/null || true
    exit 1
fi

echo "[entrypoint-cloud] KasmVNC started (PID=$KASMVNC_PID)"

# Wait for KasmVNC to be ready
echo "[entrypoint-cloud] Waiting for KasmVNC to be ready..."
RETRIES=0
while ! kill -0 $KASMVNC_PID 2>/dev/null || ! ss -tlnp 2>/dev/null | grep -q "${CLOUD_PORT}"; do
    sleep 1
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -gt 30 ]; then
        echo "[entrypoint-cloud] ERROR: KasmVNC failed to start!"
        echo "[entrypoint-cloud] KasmVNC process alive: $(kill -0 $KASMVNC_PID 2>/dev/null && echo 'yes' || echo 'no')"
        echo "[entrypoint-cloud] KasmVNC log (last 30 lines):"
        tail -30 /config/logs/kasmvnc.log 2>/dev/null || echo "(no log)"
        exit 1
    fi
    if [ $((RETRIES % 5)) -eq 0 ]; then
        echo "[entrypoint-cloud] Still waiting... (attempt $RETRIES/30, alive: $(kill -0 $KASMVNC_PID 2>/dev/null && echo 'yes' || echo 'no'))"
    fi
done
echo "[entrypoint-cloud] KasmVNC is ready on port ${CLOUD_PORT}."

# ---- Start Desktop Environment (KDE) ----
echo "[entrypoint-cloud] Starting KDE Plasma..."
if [ -f /defaults/startwm.sh ]; then
    cd /config
    run_as_abc /bin/bash /defaults/startwm.sh &
    DE_PID=$!
else
    echo "[entrypoint-cloud] WARNING: startwm.sh not found, trying startplasma-x11 directly"
    run_as_abc startplasma-x11 &
    DE_PID=$!
fi
sleep 2

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

    # Check KasmVNC
    if ! kill -0 $KASMVNC_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: KasmVNC died, restarting..."
        # Clean up stale state
        rm -f /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true
        if [ -x /usr/local/bin/Xvnc ]; then
            run_as_abc /usr/local/bin/Xvnc "${DISPLAY}" \
                ${HW3D} -drinode "${DRINODE}" \
                -disableBasicAuth -SecurityTypes None -AlwaysShared \
                -geometry "${RESOLUTION}" -sslOnly 0 \
                -websocketPort "${CLOUD_PORT}" -httpPort "${CLOUD_PORT}" \
                -interface 0.0.0.0 \
                > /config/logs/kasmvnc.log 2>&1 &
            KASMVNC_PID=$!
        fi
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

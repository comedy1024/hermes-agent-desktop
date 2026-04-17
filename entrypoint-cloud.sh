#!/bin/bash
# ================================================================
# entrypoint-cloud.sh — Cloud platform entrypoint (no s6-overlay)
# ================================================================
# This entrypoint completely bypasses s6-overlay and starts services
# manually, mimicking the linuxserver/webtop startup sequence:
#
#   1. Xvfb (virtual X display)
#   2. D-Bus (system message bus)
#   3. PulseAudio (audio, optional)
#   4. Desktop Environment (KDE via startwm.sh)
#   5. Selkies WebRTC (remote desktop streaming on port 7860)
#   6. Hermes WebUI (port 8787, localhost only)
#
# Port mapping:
#   - 7860: Selkies WebRTC desktop (ModelScope/HuggingFace default)
#   - 8787: Hermes WebUI (internal only, access via desktop browser)
# ================================================================

echo "=========================================="
echo "Hermes Agent Desktop (Cloud Mode)"
echo "=========================================="

# ---- Environment setup (match webtop defaults) ----
export HOME=/config
export USER=abc
export PUID=${PUID:-1000}
export PGID=${PGID:-1000}
export DISPLAY=${DISPLAY:-:1}
export XDG_RUNTIME_DIR=/run/user/${PUID}

# Cloud port — default 7860 for ModelScope/HuggingFace
CLOUD_PORT=${CLOUD_PORT:-7860}

# Ensure required directories exist with correct permissions
mkdir -p /config/logs /config/hermes-data /config/.cache /config/.config
mkdir -p /run /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
# Remove X lock files (must be files, not directories)
rm -rf /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true

# Fix permissions for abc user
chown -R abc:abc /config/.cache 2>/dev/null || true
chown -R abc:abc /config/.config 2>/dev/null || true
mkdir -p /run/user/${PUID}
chown abc:abc /run/user/${PUID} 2>/dev/null || true

# Fix Fontconfig cache directory
mkdir -p /config/.cache/fontconfig
chown -R abc:abc /config/.cache/fontconfig 2>/dev/null || true

# Set up user UID/GID if needed
if [ -n "$PUID" ] && [ -n "$PGID" ]; then
    groupmod -o -g "$PGID" abc 2>/dev/null || true
    usermod -o -u "$PUID" abc 2>/dev/null || true
fi

# ---- Run custom init scripts ----
# Skip 10-hermes-webui.sh in cloud mode (we start WebUI manually later)
if [ -d /custom-cont-init.d ]; then
    echo "[entrypoint] Running custom init scripts..."
    for script in /custom-cont-init.d/*.sh; do
        if [ -f "$script" ]; then
            # Skip hermes-webui.sh in cloud mode (started manually below)
            if [[ "$(basename "$script")" == *"hermes-webui"* ]]; then
                echo "[entrypoint] Skipping: $(basename "$script") (cloud mode)"
                continue
            fi
            echo "[entrypoint] Running: $(basename "$script")"
            chmod +x "$script"
            bash "$script" 2>&1 || true
        fi
    done
fi

# ---- 1. Start Xvfb (virtual X display server) ----
# Mirrors webtop's svc-xorg/run
echo "[entrypoint] Starting Xvfb..."
rm -f /tmp/.X1-lock

VFBCOMMAND=""
if ! which nvidia-smi 2>/dev/null && [ -e "/dev/dri/renderD128" ]; then
    VFBCOMMAND="-vfbdevice /dev/dri/renderD128"
fi
if [ -n "${DRINODE}" ]; then
    VFBCOMMAND="-vfbdevice ${DRINODE}"
fi
if [ "${DISABLE_DRI3}" != "false" ] 2>/dev/null; then
    VFBCOMMAND=""
fi

DEFAULT_RES="${MAX_RES:-15360x8640}"
if [ -n "${SELKIES_MANUAL_WIDTH}" ] || [ -n "${SELKIES_MANUAL_HEIGHT}" ]; then
    T_WIDTH="${SELKIES_MANUAL_WIDTH:-1024}"
    T_HEIGHT="${SELKIES_MANUAL_HEIGHT:-768}"
    [ "${T_WIDTH}" = "0" ] && T_WIDTH=1024
    [ "${T_HEIGHT}" = "0" ] && T_HEIGHT=768
    DEFAULT_RES="${T_WIDTH}x${T_HEIGHT}"
fi

s6-setuidgid abc /usr/bin/Xvfb \
    "${DISPLAY}" \
    -screen 0 "${DEFAULT_RES}x24" \
    -dpi 96 \
    +extension COMPOSITE +extension DAMAGE +extension GLX \
    +extension RANDR +extension RENDER +extension MIT-SHM \
    +extension XFIXES +extension XTEST \
    +iglx +render \
    -nolisten tcp -ac -noreset -shmem \
    ${VFBCOMMAND} &
XVFB_PID=$!

# Wait for X to be ready
echo "[entrypoint] Waiting for X server..."
RETRIES=0
while ! xset q &>/dev/null; do
    sleep 0.5
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -gt 30 ]; then
        echo "[entrypoint] ERROR: X server failed to start!"
        exit 1
    fi
done
echo "[entrypoint] X server is ready."

# ---- 2. Start D-Bus ----
echo "[entrypoint] Starting D-Bus..."
if [ -x /usr/bin/dbus-daemon ]; then
    mkdir -p /run/dbus
    dbus-daemon --system --fork 2>/dev/null || true
fi

# ---- 3. Start PulseAudio ----
echo "[entrypoint] Starting PulseAudio..."
if command -v pulseaudio >/dev/null 2>&1; then
    s6-setuidgid abc pulseaudio --start --fail=false \
        --daemonize=true 2>/dev/null || true
fi

# ---- 4. Set X resources and resolution ----
if [ -f "${HOME}/.Xresources" ]; then
    if ! grep -q "breeze_cursors" "${HOME}/.Xresources"; then
        echo "Xcursor.theme: breeze_cursors" > "${HOME}/.Xresources"
    fi
    xrdb "${HOME}/.Xresources"
else
    echo "Xcursor.theme: breeze_cursors" > "${HOME}/.Xresources"
    xrdb "${HOME}/.Xresources"
fi
chown abc:abc "${HOME}/.Xresources" 2>/dev/null || true
chmod 777 /tmp/selkies* 2>/dev/null || true

# Set resolution
RESOLUTION_WIDTH=${SELKIES_MANUAL_WIDTH:-1024}
RESOLUTION_HEIGHT=${SELKIES_MANUAL_HEIGHT:-768}
[ "${RESOLUTION_WIDTH}" = "0" ] && RESOLUTION_WIDTH=1024
[ "${RESOLUTION_HEIGHT}" = "0" ] && RESOLUTION_HEIGHT=768

MODELINE=$(s6-setuidgid abc cvt "${RESOLUTION_WIDTH}" "${RESOLUTION_HEIGHT}" 2>/dev/null | grep "Modeline" | sed 's/^.*Modeline //')
if [ -n "$MODELINE" ]; then
    MODELINE_ARGS=$(echo "$MODELINE" | tr -d '"')
    MODELINE_NAME=$(echo "$MODELINE_ARGS" | awk '{print $1}')
    if ! s6-setuidgid abc xrandr 2>/dev/null | grep -q "$MODELINE_NAME"; then
        s6-setuidgid abc xrandr --newmode $MODELINE_ARGS 2>/dev/null || true
        s6-setuidgid abc xrandr --addmode screen "$MODELINE_NAME" 2>/dev/null || true
        s6-setuidgid abc xrandr --output screen --mode "$MODELINE_NAME" --dpi 96 2>/dev/null || true
    fi
fi

# ---- 5. Start Desktop Environment ----
echo "[entrypoint] Starting desktop environment..."
if [ -f /defaults/startwm.sh ]; then
    cd /config
    s6-setuidgid abc /bin/bash /defaults/startwm.sh &
    DE_PID=$!
else
    # Fallback to openbox if webtop startwm not found
    if command -v openbox >/dev/null 2>&1; then
        HOME=/config s6-setuidgid abc openbox-session &
        DE_PID=$!
    fi
fi
sleep 2

# ---- 6. Start Selkies WebRTC (directly on CLOUD_PORT) ----
echo "[entrypoint] Starting Selkies WebRTC on port ${CLOUD_PORT}..."
if command -v selkies >/dev/null 2>&1; then
    # Set up audio sinks (mirrors svc-selkies/run)
    if [ ! -f '/dev/shm/audio.lock' ]; then
        s6-setuidgid abc with-contenv pactl \
            load-module module-null-sink \
            sink_name="output" \
            sink_properties=device.description="output" 2>/dev/null || true
        s6-setuidgid abc with-contenv pactl \
            load-module module-null-sink \
            sink_name="input" \
            sink_properties=device.description="input" 2>/dev/null || true
        touch /dev/shm/audio.lock
    fi

    export XCURSOR_THEME=breeze_cursors
    # Selkies listens directly on CLOUD_PORT (default 7860)
    # This is the entry point for cloud platform connections
    # NOTE: Removed --mode="websockets" to allow HTTP + WebSocket
    # ModelScope's reverse proxy needs HTTP for initial page load
    s6-setuidgid abc selkies \
        --addr="0.0.0.0" \
        --port="${CLOUD_PORT}" &
    SELKIES_PID=$!
    echo "[entrypoint] Selkies started on port ${CLOUD_PORT} (PID=$SELKIES_PID)"
else
    echo "[entrypoint] WARNING: selkies not found, skipping WebRTC"
fi

# ---- 7. Start Hermes WebUI (localhost only) ----
echo "[entrypoint] Starting Hermes WebUI on port 8787 (localhost only)..."
if [ -f /opt/hermes-webui-service.sh ]; then
    bash /opt/hermes-webui-service.sh &
    WEBUI_PID=$!
else
    cd /opt/hermes-webui
    /opt/hermes-venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 8787 &
    WEBUI_PID=$!
fi

echo "=========================================="
echo "All services started!"
echo "- Desktop (Selkies): http://localhost:${CLOUD_PORT}"
echo "- Hermes WebUI:      http://localhost:8787 (access via desktop browser)"
echo "=========================================="

# ---- Keep container alive and monitor services ----
while true; do
    sleep 30

    # Check Xvfb
    if ! kill -0 $XVFB_PID 2>/dev/null; then
        echo "[entrypoint] WARNING: Xvfb died, restarting..."
        rm -f /tmp/.X1-lock
        s6-setuidgid abc /usr/bin/Xvfb "${DISPLAY}" \
            -screen 0 "${DEFAULT_RES}x24" -dpi 96 \
            +extension COMPOSITE +extension DAMAGE +extension GLX \
            +extension RANDR +extension RENDER +extension MIT-SHM \
            +extension XFIXES +extension XTEST \
            +iglx +render -nolisten tcp -ac -noreset -shmem \
            ${VFBCOMMAND} &
        XVFB_PID=$!
    fi

    # Check Selkies
    if [ -n "$SELKIES_PID" ] && ! kill -0 $SELKIES_PID 2>/dev/null; then
        echo "[entrypoint] WARNING: Selkies died, restarting..."
        s6-setuidgid abc selkies \
            --addr="0.0.0.0" \
            --port="${CLOUD_PORT}" &
        SELKIES_PID=$!
    fi

    # Check WebUI
    if [ -n "$WEBUI_PID" ] && ! kill -0 $WEBUI_PID 2>/dev/null; then
        echo "[entrypoint] WARNING: Hermes WebUI died, restarting..."
        if [ -f /opt/hermes-webui-service.sh ]; then
            bash /opt/hermes-webui-service.sh &
        else
            cd /opt/hermes-webui
            /opt/hermes-venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port 8787 &
        fi
        WEBUI_PID=$!
    fi
done

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
# KEY DESIGN: Desktop components (KDE, fcitx5) run as user 'abc'
# to avoid XDG_RUNTIME_DIR UID mismatch errors.
# Only websockify and hermes services run as root.
# ================================================================

echo "=========================================="
echo "Hermes Agent Desktop (Cloud Mode)"
echo "=========================================="
echo "[entrypoint-cloud] Starting at $(date)"

# ---- Environment setup ----
export HOME=/config
export USER=abc
export PUID=${PUID:-911}
export PGID=${PGID:-1000}
export DISPLAY=${DISPLAY:-:1}
# NOTE: XDG_RUNTIME_DIR is set per-user below (must match actual UID, not env var)
export XDG_CONFIG_HOME=/config/.config
export XDG_CACHE_HOME=/config/.cache
export XDG_DATA_HOME=/config/.local/share

# Cloud port — default 7860 for ModelScope/HuggingFace
CLOUD_PORT=${CLOUD_PORT:-7860}

# Input method (fcitx5)
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx

# VNC port (internal, not exposed externally)
VNC_PORT=5901

# Resolution — 1024x768 is optimal for cloud platforms (smaller = faster + less resource usage)
# 1280x720 was too large, causing lag and UI issues on constrained cloud instances
RESOLUTION=${RESOLUTION:-1024x768}

echo "[entrypoint-cloud] Config: DISPLAY=${DISPLAY} VNC_PORT=${VNC_PORT} CLOUD_PORT=${CLOUD_PORT} RESOLUTION=${RESOLUTION}"

# ---- Ensure required directories exist ----
mkdir -p /config/logs /config/hermes-data /config/.cache /config/.config
mkdir -p /config/.vnc /config/.local/share /run /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Clean up stale X11/VNC state (critical for container restarts)
rm -f /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true
pkill -9 -f "Xtigervnc" 2>/dev/null || true
pkill -9 -f "Xvnc" 2>/dev/null || true
pkill -9 -f "websockify" 2>/dev/null || true

# ---- Fix UID/GID and permissions ----
# Ensure abc user has correct UID (baseimage-kasmvnc default is 911)
if id abc >/dev/null 2>&1; then
    echo "[entrypoint-cloud] User abc exists (UID=$(id -u abc))"
else
    echo "[entrypoint-cloud] Creating user abc (UID=${PUID})"
    useradd -u ${PUID} -m -s /bin/bash abc 2>/dev/null || true
fi

# Fix XDG_RUNTIME_DIR ownership (critical — prevents "not owned by UID" errors)
mkdir -p /run/user/${PUID}
chown abc:abc /run/user/${PUID}
chmod 700 /run/user/${PUID}

# Fix config directory ownership
chown -R abc:abc /config/.cache /config/.config /config/.vnc /config/.local 2>/dev/null || true

# Fix config directory ownership
mkdir -p /config/.cache/fontconfig
chown -R abc:abc /config/.cache/fontconfig 2>/dev/null || true

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
# Start TigerVNC — as root (needs to bind port and create display)
# ================================================================
echo "[entrypoint-cloud] Starting TigerVNC on ${DISPLAY} (${RESOLUTION})..."

if [ ! -x /usr/bin/Xtigervnc ]; then
    echo "[entrypoint-cloud] ERROR: /usr/bin/Xtigervnc not found!"
    exit 1
fi

# Create VNC password directory
mkdir -p /config/.vnc
chown abc:abc /config/.vnc 2>/dev/null || true

# Start TigerVNC server
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
        echo "[entrypoint-cloud] Still waiting... (attempt $RETRIES/30)"
    fi
done
echo "[entrypoint-cloud] VNC server is ready on port ${VNC_PORT}."

# ================================================================
# Start Desktop Environment (KDE) — as user 'abc'
# ================================================================
# This is CRITICAL: KDE must run as the same user that owns
# XDG_RUNTIME_DIR (/run/user/911). Running as root causes:
#   - "runtime directory not owned by UID 0" errors
#   - kwin_x11 crash (window manager) → no window decorations
#   - Activity manager not running → shell load abort
#   - D-Bus signal failures → menu freeze, desktop hang
#   - Polkit authentication failure → dialogs freeze
#
# IMPORTANT: /defaults/startwm.sh has Permission denied issues in
# cloud environments (possibly due to overlay filesystem restrictions).
# We copy it to /tmp/ where abc definitely has access.
# ================================================================

# Ensure ALL XDG/runtime dirs are correctly owned by abc
mkdir -p /run/user/${PUID}
chown -R abc:abc /run/user/${PUID}
chmod 700 /run/user/${PUID}

# Also fix /run/user/1000 if it exists (baseimage-kasmvnc may create it)
if [ -d /run/user/1000 ]; then
    chown -R abc:abc /run/user/1000
    chmod 700 /run/user/1000
fi

echo "[entrypoint-cloud] Starting KDE Plasma as user abc (UID=${PUID})..."

# Ensure ICEauthority and Xauthority exist for abc
touch /config/.ICEauthority /config/.Xauthority 2>/dev/null || true
chown abc:abc /config/.ICEauthority /config/.Xauthority 2>/dev/null || true

# CRITICAL: Set XDG_RUNTIME_DIR to match the UID of abc user
ABC_UID=$(id -u abc)
ABC_XDG_RUNTIME_DIR="/run/user/${ABC_UID}"
mkdir -p "${ABC_XDG_RUNTIME_DIR}"
chown abc:abc "${ABC_XDG_RUNTIME_DIR}"
chmod 700 "${ABC_XDG_RUNTIME_DIR}"

echo "[entrypoint-cloud] abc UID=${ABC_UID}, XDG_RUNTIME_DIR=${ABC_XDG_RUNTIME_DIR}"

# ---- Copy startwm.sh to /tmp/ where abc can access it ----
# /defaults/ may have overlay filesystem restrictions that prevent
# non-root users from reading files, even with 755 permissions.
# /tmp/ is always accessible to all users.
if [ -f /defaults/startwm.sh ]; then
    cp /defaults/startwm.sh /tmp/startwm.sh
    chmod 755 /tmp/startwm.sh
    chown abc:abc /tmp/startwm.sh
    echo "[entrypoint-cloud] Copied startwm.sh to /tmp/ (permissions: $(ls -la /tmp/startwm.sh))"
fi

# Use runuser instead of su — it preserves environment variables correctly
# and doesn't reset them by reading .profile/.bashrc like su - does.
if [ -x /tmp/startwm.sh ]; then
    runuser -u abc -- env \
        DISPLAY="${DISPLAY}" \
        HOME=/config \
        USER=abc \
        XDG_RUNTIME_DIR="${ABC_XDG_RUNTIME_DIR}" \
        XDG_CONFIG_HOME=/config/.config \
        XDG_CACHE_HOME=/config/.cache \
        XDG_DATA_HOME=/config/.local/share \
        GTK_IM_MODULE=fcitx \
        QT_IM_MODULE=fcitx \
        XMODIFIERS=@im=fcitx \
        SDL_IM_MODULE=fcitx \
        /bin/bash /tmp/startwm.sh &
    DE_PID=$!
else
    runuser -u abc -- env \
        DISPLAY="${DISPLAY}" \
        HOME=/config \
        USER=abc \
        XDG_RUNTIME_DIR="${ABC_XDG_RUNTIME_DIR}" \
        XDG_CONFIG_HOME=/config/.config \
        XDG_CACHE_HOME=/config/.cache \
        XDG_DATA_HOME=/config/.local/share \
        GTK_IM_MODULE=fcitx \
        QT_IM_MODULE=fcitx \
        XMODIFIERS=@im=fcitx \
        SDL_IM_MODULE=fcitx \
        startplasma-x11 &
    DE_PID=$!
fi
sleep 2

# Wait for D-Bus session bus to be available (started by startwm.sh's dbus-launch)
# Write the bus address to a file so Chrome and other processes can find it
echo "[entrypoint-cloud] Waiting for D-Bus session bus..."
DBUS_WAIT=0
while [ $DBUS_WAIT -lt 15 ]; do
    if [ -S "${ABC_XDG_RUNTIME_DIR}/bus" ]; then
        echo "[entrypoint-cloud] D-Bus session bus is ready at ${ABC_XDG_RUNTIME_DIR}/bus"
        break
    fi
    # Also check for dbus-launch output file
    if [ -f "${ABC_XDG_RUNTIME_DIR}/dbus-session-address" ]; then
        echo "[entrypoint-cloud] D-Bus session address file found"
        break
    fi
    sleep 1
    DBUS_WAIT=$((DBUS_WAIT + 1))
done

# ================================================================
# Start noVNC + websockify — bridges VNC to WebSocket/HTTP
# ================================================================
echo "[entrypoint-cloud] Starting noVNC on port ${CLOUD_PORT}..."

NOVNC_WEB=""
if [ -d /usr/share/novnc ]; then
    NOVNC_WEB=/usr/share/novnc
elif [ -d /opt/novnc ]; then
    NOVNC_WEB=/opt/novnc
fi

WEBSOCKIFY_BIN=""
if [ -x /usr/bin/websockify ]; then
    WEBSOCKIFY_BIN=/usr/bin/websockify
elif command -v websockify >/dev/null 2>&1; then
    WEBSOCKIFY_BIN=$(which websockify)
fi

if [ -z "$WEBSOCKIFY_BIN" ]; then
    echo "[entrypoint-cloud] ERROR: websockify not found!"
    exit 1
fi

echo "[entrypoint-cloud] Using websockify: ${WEBSOCKIFY_BIN}"
if [ -n "$NOVNC_WEB" ]; then
    echo "[entrypoint-cloud] noVNC web root: ${NOVNC_WEB}"
    # Create index.html that directly loads the VNC client with auto-connect
    # KEY: Use vnc.html with autoconnect=true to skip the Connect button
    # Also set resize=scale to fit the browser window
    cat > "${NOVNC_WEB}/index.html" << 'NOVNC_INDEX_EOF'
<!DOCTYPE html>
<html>
<head>
<title>Hermes Agent Desktop</title>
<style>
    body { margin: 0; padding: 0; overflow: hidden; background: #000; }
</style>
</head>
<body>
<iframe id="vnc_frame" src="vnc.html?autoconnect=true&resize=scale" 
    style="width:100vw;height:100vh;border:none;margin:0;padding:0;"></iframe>
</body>
</html>
NOVNC_INDEX_EOF
        echo "[entrypoint-cloud] Created index.html with auto-connect to VNC"
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

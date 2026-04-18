#!/bin/bash
# ================================================================
# entrypoint-cloud.sh — Cloud platform entrypoint with Nginx
# ================================================================
# This entrypoint configures webtop's built-in Nginx to listen on
# the cloud platform's port (default 7860) instead of 3000/3001.
#
# Architecture:
#   Browser → Nginx (7860) → Selkies WebSocket (8082)
#
# We keep Nginx because:
#   1. It's part of webtop base image and handles WebSocket upgrade
#   2. ModelScope's reverse proxy sends HTTP first, then WebSocket
#   3. Nginx bridges this gap by handling both protocols
# ================================================================

echo "=========================================="
echo "Hermes Agent Desktop (Cloud Mode)"
echo "=========================================="
echo "[entrypoint-cloud] Starting at $(date)"
echo "[entrypoint-cloud] Script version: 288608g (standalone nginx.conf + server fragment)"

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

# ---- Configure Nginx for cloud port ----
# webtop's Nginx architecture:
#   /etc/nginx/nginx.conf          — main config (has http { include site-confs/* })
#   /defaults/default.conf         — server block template (included by main config)
#   /config/nginx/site-confs/      — persistent server configs (copied from /defaults/)
#
# The server block in /defaults/default.conf contains:
#   listen 3000 / listen 3001 ssl → proxies to Selkies on 8082
#
# Strategy: create a complete standalone nginx.conf that includes the
# modified server block, so `nginx -c <file>` works as a standalone config.
echo "[entrypoint-cloud] Configuring Nginx for port ${CLOUD_PORT}..."

# Clean up stale nginx configs from previous runs (persistent volume)
rm -f /config/nginx/nginx.conf /config/nginx/cloud-server.conf
mkdir -p /config/nginx /config/logs

if [ -f /defaults/default.conf ]; then
    echo "[entrypoint-cloud] Found webtop default.conf, building standalone config..."

    # Build a modified server block from the template
    # Replace ports 3000/3001 → CLOUD_PORT
    sed -e "s/listen 3000 default_server/listen ${CLOUD_PORT} default_server/g" \
        -e "s/listen 3001 default_server ssl/listen ${CLOUD_PORT} default_server ssl/g" \
        -e "s/listen \[::\]:3000 default_server/listen [::]:${CLOUD_PORT} default_server/g" \
        -e "s/listen \[::\]:3001 default_server ssl/listen [::]:${CLOUD_PORT} default_server ssl/g" \
        /defaults/default.conf > /config/nginx/cloud-server.conf

    # Build a complete nginx.conf that includes the server block
    cat > /config/nginx/nginx.conf << 'NGINXMAIN'
worker_processes auto;
error_log /config/logs/nginx-error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    # Cloud mode server block (port modified from webtop template)
    include /config/nginx/cloud-server.conf;
}
NGINXMAIN

    echo "[entrypoint-cloud] Standalone nginx.conf + cloud-server.conf created (port ${CLOUD_PORT})"
else
    echo "[entrypoint-cloud] WARNING: /defaults/default.conf not found, creating minimal standalone config"

    # Build a complete standalone nginx.conf from scratch
    cat > /config/nginx/nginx.conf << NGINXMINIMAL
worker_processes auto;
error_log /config/logs/nginx-error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    server {
        listen ${CLOUD_PORT};

        location / {
            proxy_pass http://127.0.0.1:8082;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
        }
    }
}
NGINXMINIMAL

    echo "[entrypoint-cloud] Minimal standalone nginx.conf created (port ${CLOUD_PORT})"
fi

# Validate nginx config before starting
echo "[entrypoint-cloud] Validating Nginx config..."
nginx -t -c /config/nginx/nginx.conf 2>&1 || {
    echo "[entrypoint-cloud] ERROR: Nginx config validation failed!"
    echo "[entrypoint-cloud] Dumping nginx.conf for debug:"
    cat /config/nginx/nginx.conf
    if [ -f /config/nginx/cloud-server.conf ]; then
        echo "[entrypoint-cloud] Dumping cloud-server.conf for debug:"
        cat /config/nginx/cloud-server.conf
    fi
}

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

# ---- Set X resources ----
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

# ---- Start Desktop Environment ----
echo "[entrypoint-cloud] Starting desktop environment..."
if [ -f /defaults/startwm.sh ]; then
    cd /config
    s6-setuidgid abc /bin/bash /defaults/startwm.sh &
    DE_PID=$!
else
    if command -v openbox >/dev/null 2>&1; then
        HOME=/config s6-setuidgid abc openbox-session &
        DE_PID=$!
    fi
fi
sleep 2

# ---- Start Selkies WebRTC (on default port 8082) ----
echo "[entrypoint-cloud] Starting Selkies WebRTC on port 8082..."
if command -v selkies >/dev/null 2>&1; then
    # Set up audio sinks
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
    # Selkies listens on 8082 (default), Nginx will proxy to it
    s6-setuidgid abc selkies &
    SELKIES_PID=$!
    echo "[entrypoint-cloud] Selkies started on port 8082 (PID=$SELKIES_PID)"
else
    echo "[entrypoint-cloud] WARNING: selkies not found, skipping WebRTC"
fi

# ---- Start Nginx with custom config ----
echo "[entrypoint-cloud] Starting Nginx on port ${CLOUD_PORT}..."
NGINX_OK=false
if command -v nginx >/dev/null 2>&1; then
    if nginx -t -c /config/nginx/nginx.conf 2>/dev/null; then
        NGINX_OK=true
        nginx -c /config/nginx/nginx.conf &
        NGINX_PID=$!
        echo "[entrypoint-cloud] Nginx started on port ${CLOUD_PORT} (PID=$NGINX_PID)"
    else
        echo "[entrypoint-cloud] ERROR: Nginx config invalid, NOT starting nginx"
        echo "[entrypoint-cloud] Selkies will be accessible directly on port 8082"
    fi
else
    echo "[entrypoint-cloud] WARNING: nginx not found"
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
echo "- Nginx (proxy):     http://localhost:${CLOUD_PORT}"
echo "- Selkies (backend): ws://localhost:8082"
echo "- Hermes WebUI:      http://localhost:8648"
echo "- Hermes Gateway:    http://localhost:8642"
echo "=========================================="

# ---- Keep container alive and monitor services ----
while true; do
    sleep 30

    # Check Xvfb
    if ! kill -0 $XVFB_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: Xvfb died, restarting..."
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
        echo "[entrypoint-cloud] WARNING: Selkies died, restarting..."
        s6-setuidgid abc selkies &
        SELKIES_PID=$!
    fi

    # Check Nginx (only if config was valid)
    if [ "$NGINX_OK" = "true" ] && [ -n "$NGINX_PID" ] && ! kill -0 $NGINX_PID 2>/dev/null; then
        echo "[entrypoint-cloud] WARNING: Nginx died, restarting..."
        if nginx -t -c /config/nginx/nginx.conf 2>/dev/null; then
            nginx -c /config/nginx/nginx.conf &
            NGINX_PID=$!
        else
            echo "[entrypoint-cloud] ERROR: Nginx config invalid on restart, giving up"
            NGINX_OK=false
        fi
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

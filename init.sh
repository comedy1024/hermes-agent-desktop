#!/bin/bash
# ================================================================
# init.sh — Custom init for cloud platforms (no s6-overlay)
# ================================================================
# This replaces the s6-overlay init for platforms that don't support
# PID 1 requirements (ModelScope Spaces, etc.)
#
# Instead of using s6-overlay's complex service management, we manually
# start the essential services that webtop needs.
# ================================================================

set -e

echo "[init] Starting Hermes Agent Desktop (cloud mode)..."

# Create necessary directories
mkdir -p /config/logs /config/hermes-data /run/s6 /run/s6/services

# Set up environment
export HOME=/config
export USER=abc
export PGID=1000
export PUID=1000

# Start s6-svscan in background (for legacy compatibility)
if [ -d /etc/s6 ]; then
    echo "[init] Starting s6-svscan..."
    /bin/s6-svscan /etc/s6 &
    S6_PID=$!
    sleep 1
fi

# Run custom init scripts
if [ -d /custom-cont-init.d ]; then
    echo "[init] Running custom init scripts..."
    for script in /custom-cont-init.d/*.sh; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            echo "[init] Running: $script"
            "$script" || true
        fi
    done
fi

# Start webtop services manually
echo "[init] Starting webtop services..."

# Start dbus
if [ -f /etc/init.d/dbus ]; then
    /etc/init.d/dbus start || true
fi

# Start Xvfb and noVNC
export DISPLAY=:1
export WEB_PORT=3000

# Start X server
Xvfb :1 -screen 0 1920x1080x24 &
XVFB_PID=$!
sleep 2

# Start KDE Plasma (or fallback to openbox)
if command -v startplasma-x11 >/dev/null 2>&1; then
    su - abc -c "DISPLAY=:1 startplasma-x11" &
elif command -v openbox >/dev/null 2>&1; then
    su - abc -c "DISPLAY=:1 openbox" &
fi

# Start noVNC
/usr/local/bin/novnc_server --vnc localhost:5900 --listen $WEB_PORT &
NOVNC_PID=$!

# Start websockify for VNC
if command -v websockify >/dev/null 2>&1; then
    websockify --web=/usr/share/novnc $WEB_PORT localhost:5900 &
fi

echo "[init] Web services started on port $WEB_PORT"

# Start Hermes WebUI
echo "[init] Starting Hermes WebUI..."
nohup /opt/hermes-webui-service.sh > /config/logs/hermes-webui.log 2>&1 &

# Keep the container running
echo "[init] All services started. Keeping container alive..."
while true; do
    sleep 60
    # Health check
    if ! pgrep -f "novnc" > /dev/null; then
        echo "[init] Warning: noVNC not running"
    fi
done

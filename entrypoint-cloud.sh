#!/bin/bash
# ================================================================
# entrypoint-cloud.sh — Cloud platform entrypoint (no s6-overlay dependency)
# ================================================================
# This entrypoint completely bypasses s6-overlay and starts services manually.
# Designed for ModelScope Spaces and similar platforms that don't allow
# the container to run as PID 1.
# ================================================================

set -e

echo "=========================================="
echo "Hermes Agent Desktop (Cloud Mode)"
echo "=========================================="

# Environment setup
export HOME=/config
export USER=abc
export PUID=${PUID:-1000}
export PGID=${PGID:-1000}
export DISPLAY=:1

# Ensure required directories exist
mkdir -p /config/logs /config/hermes-data /run /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Set up user permissions
if [ -n "$PUID" ] && [ -n "$PGID" ]; then
    groupmod -o -g "$PGID" abc 2>/dev/null || true
    usermod -o -u "$PUID" abc 2>/dev/null || true
fi

# Run custom init scripts
if [ -d /custom-cont-init.d ]; then
    echo "[entrypoint] Running custom init scripts..."
    for script in /custom-cont-init.d/*.sh; do
        if [ -f "$script" ]; then
            echo "[entrypoint] Running: $(basename "$script")"
            chmod +x "$script"
            bash "$script" 2>&1 || true
        fi
    done
fi

# Start X virtual framebuffer (Xvfb) for headless desktop
echo "[entrypoint] Starting Xvfb..."
Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 2

# Start window manager (OpenBox as lightweight fallback)
echo "[entrypoint] Starting window manager..."
if command -v openbox >/dev/null 2>&1; then
    su - abc -c "DISPLAY=:1 openbox-session" &
elif command -v fluxbox >/dev/null 2>&1; then
    su - abc -c "DISPLAY=:1 fluxbox" &
fi
sleep 1

# Start VNC server
echo "[entrypoint] Starting VNC server..."
if command -v x11vnc >/dev/null 2>&1; then
    x11vnc -display :1 -nopw -listen localhost -xkb -forever -shared &
    X11VNC_PID=$!
elif command -v Xtigervnc >/dev/null 2>&1; then
    su - abc -c "Xtigervnc :1 -geometry 1920x1080 -depth 24 -SecurityTypes None" &
fi
sleep 1

# Start noVNC web server
echo "[entrypoint] Starting noVNC on port 3000..."
if [ -d /usr/share/novnc ]; then
    # Use websockify to bridge WebSocket to VNC
    websockify --web=/usr/share/novnc --cert=none 3000 localhost:5900 &
    WEBSOCKIFY_PID=$!
elif [ -f /usr/local/bin/novnc_server ]; then
    /usr/local/bin/novnc_server --vnc localhost:5900 --listen 3000 &
    NOVNC_PID=$!
fi

# Start Hermes WebUI
echo "[entrypoint] Starting Hermes WebUI on port 8787..."
if [ -f /opt/hermes-webui-service.sh ]; then
    bash /opt/hermes-webui-service.sh &
    WEBUI_PID=$!
else
    # Fallback: start webui directly
    cd /opt/hermes-webui
    /opt/hermes-venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8787 &
    WEBUI_PID=$!
fi

echo "=========================================="
echo "All services started!"
echo "- noVNC Desktop: http://localhost:3000"
echo "- Hermes WebUI: http://localhost:8787"
echo "=========================================="

# Keep container alive and monitor services
while true; do
    sleep 30
    
    # Check Xvfb
    if ! kill -0 $XVFB_PID 2>/dev/null; then
        echo "[entrypoint] Warning: Xvfb died, restarting..."
        Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
        XVFB_PID=$!
    fi
    
    # Check WebUI
    if ! kill -0 $WEBUI_PID 2>/dev/null; then
        echo "[entrypoint] Warning: Hermes WebUI died, restarting..."
        if [ -f /opt/hermes-webui-service.sh ]; then
            bash /opt/hermes-webui-service.sh &
        else
            cd /opt/hermes-webui
            /opt/hermes-venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8787 &
        fi
        WEBUI_PID=$!
    fi
done

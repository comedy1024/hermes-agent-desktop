#!/bin/bash
# ================================================================
# cloud-init.sh — Simplified init for cloud platforms
# ================================================================
# This script bypasses s6-overlay entirely and starts services directly.
# Designed for platforms like ModelScope Spaces that don't support
# s6-overlay's PID 1 requirement.
# ================================================================

set -e

echo "[cloud-init] Hermes Agent Desktop starting..."

# Basic environment setup
export HOME=/config
export USER=abc
export PUID=${PUID:-1000}
export PGID=${PGID:-1000}

# Ensure directories exist
mkdir -p /config/logs /config/hermes-data /run /tmp

# Run bootstrap scripts first
if [ -d /custom-cont-init.d ]; then
    echo "[cloud-init] Running bootstrap scripts..."
    for script in /custom-cont-init.d/*.sh; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            echo "[cloud-init] Executing: $(basename $script)"
            bash "$script" 2>&1 | tee -a /config/logs/init.log || true
        fi
    done
fi

# Start the essential services from s6-overlay manually
# These are normally managed by s6, but we start them directly

echo "[cloud-init] Starting core services..."

# Source any environment files
[ -f /etc/s6/s6.conf ] && source /etc/s6/s6.conf 2>/dev/null || true

# Start s6-svscan with services directory
if [ -d /etc/s6/services ]; then
    echo "[cloud-init] Starting s6 service manager..."
    # Run s6-svscan in a subshell - it doesn't need to be PID 1
    (
        cd /etc/s6/services
        # Start each service manually
        for svc in */; do
            svc=${svc%/}
            if [ -f "/etc/s6/services/$svc/run" ]; then
                echo "[cloud-init] Starting service: $svc"
                mkdir -p "/etc/s6/services/$svc/supervise"
                bash "/etc/s6/services/$svc/run" &
            fi
        done
    )
fi

# Wait a moment for services to initialize
sleep 3

# Start Hermes WebUI directly
echo "[cloud-init] Starting Hermes WebUI..."
if [ -f /opt/hermes-webui-service.sh ]; then
    bash /opt/hermes-webui-service.sh &
fi

echo "[cloud-init] All services started!"
echo "[cloud-init] Container is now running."

# Keep container alive with a simple loop
# This replaces the need for s6-overlay's PID 1
while true; do
    sleep 30
    # Simple health check - restart critical services if needed
    if ! pgrep -f "hermes-webui" > /dev/null 2>&1; then
        echo "[cloud-init] Restarting Hermes WebUI..."
        bash /opt/hermes-webui-service.sh 2>&1 &
    fi
done

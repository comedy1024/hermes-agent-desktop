#!/bin/bash
# ================================================================
# /init — PID 1 compatibility wrapper for s6-overlay
# ================================================================
# Problem: s6-overlay (used by linuxserver/baseimage-kasmvnc) MUST run as PID 1.
# Cloud platforms like ModelScope Spaces run: /bin/sh -c /init
# This wraps /init in a subprocess, preventing s6-overlay from becoming PID 1,
# causing: "s6-overlay-suexec: fatal: can only run as pid 1"
#
# Solution: 
#   - If PID 1: exec original s6-overlay init directly
#   - If not PID 1: Try unshare first, if that fails (no CAP_SYS_ADMIN),
#     fall back to cloud-init mode (bypass s6-overlay entirely)
# ================================================================

# Check if we're running as PID 1
if [ "$$" -eq 1 ]; then
    # Already PID 1 — normal Docker runtime
    exec /init.s6 "$@"
fi

# Not PID 1 — cloud platform wraps us in a subprocess
echo "[s6-init] Not running as PID 1 (current PID=$$), attempting PID namespace..."

# Try unshare first (requires CAP_SYS_ADMIN)
if unshare --pid --mount-proc --fork echo test > /dev/null 2>&1; then
    echo "[s6-init] unshare available, creating PID namespace..."
    exec unshare --pid --mount-proc --fork /init.s6 "$@"
fi

# unshare failed — we're in a restricted environment (no CAP_SYS_ADMIN)
echo "[s6-init] unshare not permitted (no CAP_SYS_ADMIN)"
echo "[s6-init] Falling back to cloud-init mode (bypassing s6-overlay)..."

# Fall back to cloud-init mode - completely bypass s6-overlay
exec /entrypoint-cloud.sh "$@"

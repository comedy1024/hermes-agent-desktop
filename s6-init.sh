#!/bin/sh
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

# Runtime diagnostics — helps debug "not found" issues on cloud platforms
echo "[/init] ===== WRAPPER STARTED ====="
echo "[/init] PID=$$  PPID=$PPID  SHELL=$0"
echo "[/init] /init type: $(ls -la /init 2>&1)"
echo "[/init] /init.s6 type: $(ls -la /init.s6 2>&1)"
echo "[/init] /init first line: $(head -1 /init 2>&1)"
echo "[/init] /entrypoint-cloud.sh: $(ls -la /entrypoint-cloud.sh 2>&1)"

# Check if we're running as PID 1
if [ "$$" -eq 1 ]; then
    # Already PID 1 — normal Docker runtime
    echo "[/init] PID 1 detected, exec /init.s6"
    exec /init.s6 "$@"
fi

# Not PID 1 — cloud platform wraps us in a subprocess
echo "[/init] Not PID 1 (PID=$$), attempting PID namespace..."

# Try unshare first (requires CAP_SYS_ADMIN)
if unshare --pid --mount-proc --fork echo test > /dev/null 2>&1; then
    echo "[/init] unshare available, creating PID namespace..."
    exec unshare --pid --mount-proc --fork /init.s6 "$@"
fi

# unshare failed — we're in a restricted environment (no CAP_SYS_ADMIN)
echo "[/init] unshare not permitted (no CAP_SYS_ADMIN)"
echo "[/init] Falling back to cloud-init mode (bypassing s6-overlay)..."

# Fall back to cloud-init mode - completely bypass s6-overlay
exec /entrypoint-cloud.sh "$@"

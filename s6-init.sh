#!/bin/bash
# ================================================================
# s6-init.sh — Wrapper to ensure s6-overlay runs as PID 1
# ================================================================
# Problem: s6-overlay (used by linuxserver/webtop) MUST run as PID 1.
# Cloud platforms like ModelScope Spaces wrap the container's entrypoint
# in a subprocess (e.g., /bin/sh -c /init), preventing s6-overlay from
# becoming PID 1, causing: "s6-overlay-suexec: fatal: can only run as pid 1"
#
# Solution: Use Linux PID namespace isolation via `unshare --pid`.
# When we're not PID 1, create a new PID namespace where /init becomes PID 1.
# When we're already PID 1 (normal Docker), just exec /init directly.
# ================================================================

if [ "$$" -eq 1 ]; then
    # Already PID 1 — normal Docker runtime, run s6-overlay directly
    exec /init "$@"
else
    # Not PID 1 — cloud platform (ModelScope Spaces, etc.) wraps us in a subprocess
    # Create a new PID namespace so /init becomes PID 1 inside it
    echo "[s6-init] Not running as PID 1 (current PID=$$), creating PID namespace..."
    exec unshare --pid --mount-proc --fork /init "$@"
fi

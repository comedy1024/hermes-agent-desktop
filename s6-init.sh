#!/bin/bash
# ================================================================
# /init — PID 1 compatibility wrapper for s6-overlay
# ================================================================
# Problem: s6-overlay (used by linuxserver/webtop) MUST run as PID 1.
# Cloud platforms like ModelScope Spaces run: /bin/sh -c /init
# This wraps /init in a subprocess, preventing s6-overlay from becoming PID 1,
# causing: "s6-overlay-suexec: fatal: can only run as pid 1"
#
# Solution: Replace /init with this wrapper. The original s6-overlay init
# is moved to /init.s6. This wrapper checks if we're PID 1:
#   - If yes: exec /init.s6 directly (normal Docker, zero overhead)
#   - If no: use `unshare --pid` to create a new PID namespace,
#     then exec /init.s6 inside it (becomes PID 1 in the new namespace)
# ================================================================

if [ "$$" -eq 1 ]; then
    # Already PID 1 — normal Docker runtime
    exec /init.s6 "$@"
else
    # Not PID 1 — cloud platform wraps us in a subprocess
    echo "[s6-init] Not running as PID 1 (current PID=$$), creating PID namespace..."
    exec unshare --pid --mount-proc --fork /init.s6 "$@"
fi

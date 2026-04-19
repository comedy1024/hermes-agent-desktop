#!/bin/sh
# ================================================================
# startwm.sh — Start KDE Plasma desktop
# ================================================================
# Called by:
#   1. baseimage-kasmvnc s6-overlay (normal Docker mode)
#   2. entrypoint-cloud.sh via su - abc (cloud mode)
#
# In cloud mode, environment variables are passed through su.
# In s6 mode, they need to be set here.
#
# KEY: XDG_RUNTIME_DIR MUST match the UID of the current user.
# If running as abc (UID=911), it must be /run/user/911.
# If it's wrong, KDE components will fail with:
#   - "runtime directory not owned by UID" errors
#   - kwin_x11 crash (no window manager)
#   - kactivitymanagerd not running (shell load abort)
#   - Desktop freezes, menus don't work
# ================================================================

# Ensure input method environment (may already be set by caller)
export GTK_IM_MODULE=${GTK_IM_MODULE:-fcitx}
export QT_IM_MODULE=${QT_IM_MODULE:-fcitx}
export XMODIFIERS=${XMODIFIERS:-@im=fcitx}
export SDL_IM_MODULE=${SDL_IM_MODULE:-fcitx}

# Ensure XDG dirs — CRITICAL: XDG_RUNTIME_DIR must match current UID
CURRENT_UID=$(id -u)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/${CURRENT_UID}}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# Create and fix ownership of XDG_RUNTIME_DIR
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
chown ${CURRENT_UID}:${CURRENT_UID} "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

echo "[startwm] Running as UID=${CURRENT_UID}, XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"

# Disable KDE lock screen (critical for VNC — no physical screen to unlock)
mkdir -p "$XDG_CONFIG_HOME"
if [ ! -f "$XDG_CONFIG_HOME/kscreenlockerrc" ]; then
    cat > "$XDG_CONFIG_HOME/kscreenlockerrc" << 'EOF'
[Daemon]
Autolock=false
LockOnResume=false
Timeout=0
EOF
fi

# Also disable via kwriteconfig (more reliable)
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false 2>/dev/null || true
kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume false 2>/dev/null || true
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Timeout 0 2>/dev/null || true

# Disable KDE power management (screen sleep/hibernate)
kwriteconfig5 --file powermanagementprofilesrc --group Battery --key DimDisplay false 2>/dev/null || true
kwriteconfig5 --file powermanagementprofilesrc --group Battery --key LockScreen false 2>/dev/null || true
kwriteconfig5 --file powermanagementprofilesrc --group Battery --key SleepOnPowerButton false 2>/dev/null || true
kwriteconfig5 --file powermanagementprofilesrc --group AC --key DimDisplay false 2>/dev/null || true
kwriteconfig5 --file powermanagementprofilesrc --group AC --key LockScreen false 2>/dev/null || true
kwriteconfig5 --file powermanagementprofilesrc --group AC --key SleepOnPowerButton false 2>/dev/null || true

# Disable Baloo file indexing (wastes CPU in VNC)
balooctl6 disable 2>/dev/null || true

# Start D-Bus session bus if not already running
# CRITICAL: Write the session address to a file so other processes (Chrome, etc.)
# can find it. Without this, Chrome shows "Failed to connect to the bus" errors.
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax 2>/dev/null) || true
    echo "[startwm] Started D-Bus session: $DBUS_SESSION_BUS_ADDRESS"
    # Save D-Bus session address for other processes
    if [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
        echo "$DBUS_SESSION_BUS_ADDRESS" > "${XDG_RUNTIME_DIR}/dbus-session-address"
        chmod 600 "${XDG_RUNTIME_DIR}/dbus-session-address" 2>/dev/null || true
    fi
fi

# Start fcitx5 input method daemon
if command -v fcitx5 >/dev/null 2>&1; then
    fcitx5 -d --replace 2>/dev/null &
fi

# Apply wallpaper before starting desktop
if [ -x /opt/apply-wallpaper.sh ]; then
    /opt/apply-wallpaper.sh &
fi

# Start KDE Plasma
if command -v startplasma-x11 >/dev/null 2>&1; then
    exec startplasma-x11
elif command -v startkde >/dev/null 2>&1; then
    exec startkde
else
    echo "[startwm] WARNING: KDE not found, falling back to openbox"
    exec openbox-session
fi

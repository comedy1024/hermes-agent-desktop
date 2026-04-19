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
# ================================================================

# Ensure input method environment (may already be set by caller)
export GTK_IM_MODULE=${GTK_IM_MODULE:-fcitx}
export QT_IM_MODULE=${QT_IM_MODULE:-fcitx}
export XMODIFIERS=${XMODIFIERS:-@im=fcitx}
export SDL_IM_MODULE=${SDL_IM_MODULE:-fcitx}

# Ensure XDG dirs
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

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

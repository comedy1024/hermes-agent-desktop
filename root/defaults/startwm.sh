#!/bin/sh
# ================================================================
# startwm.sh — Start KDE Plasma desktop for KasmVNC
# ================================================================
# This file replaces the default Openbox window manager.
# baseimage-kasmvnc will execute this script to start the desktop.
# ================================================================

# Set up input method environment (fcitx5)
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus

# Disable KDE lock screen (critical for VNC — no physical screen to unlock)
mkdir -p /config/.config
if [ ! -f /config/.config/kscreenlockerrc ]; then
    cat > /config/.config/kscreenlockerrc << 'EOF'
[Daemon]
Autolock=false
LockOnResume=false
Timeout=0
EOF
fi
# Also disable via kwriteconfig (more reliable)
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock --delete 2>/dev/null || true
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
# Low level — also inhibit systemd/logind sleep
mkdir -p /etc/systemd/logind.conf.d 2>/dev/null || true
cat > /etc/systemd/logind.conf.d/50-no-sleep.conf << 'LOGIND_EOF' 2>/dev/null || true
[Login]
HandleLidSwitch=ignore
HandlePowerKey=ignore
IdleAction=ignore
LOGIND_EOF

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

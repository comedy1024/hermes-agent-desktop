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

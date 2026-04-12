#!/bin/bash
# ================================================================
# rebrand.sh - Replace OpenClaw branding with Hermes Agent Desktop
# This script runs during Docker build to remove all OpenClaw
# branding including: noVNC watermark, KDE wallpaper, desktop
# shortcuts, autostart entries, and any other brand references.
# ================================================================
set -e

echo "[rebrand] Starting Hermes Agent Desktop rebranding..."

# ---- 1. Find and replace noVNC watermark/logo ----
# noVNC typically stores its web UI in /usr/share/novnc/ or /opt/noVNC/
# The watermark is usually in vnc.html or an overlay CSS/JS file
NOVNC_DIRS="/usr/share/novnc /opt/noVNC /usr/share/websockify /opt/websockify"

for dir in $NOVNC_DIRS; do
    if [ -d "$dir" ]; then
        echo "[rebrand] Scanning noVNC directory: $dir"

        # Find HTML files that might contain branding
        find "$dir" -name '*.html' -o -name '*.js' -o -name '*.css' | while read f; do
            # Check for OpenClaw/tunmax references
            if grep -li 'openclaw\|tunmax\|by b\.z\|OpenClaw_Computer' "$f" 2>/dev/null; then
                echo "[rebrand] Found branding in: $f"
                # Replace brand text
                sed -i 's/tunmax\/OpenClaw_Computer/comedy1024\/hermes-agent-desktop/g' "$f"
                sed -i 's/tunmax\/openclaw_computer/comedy1024\/hermes-agent-desktop/g' "$f"
                sed -i 's/OpenClaw_Computer/Hermes Agent Desktop/g' "$f"
                sed -i 's/OpenClaw Computer/Hermes Agent Desktop/g' "$f"
                sed -i 's/openclaw_computer/hermes-agent-desktop/g' "$f"
                sed -i 's/by b\.z/by comedy1024/g' "$f"
                sed -i 's/by b\.z\./by comedy1024/g' "$f"
                sed -i 's/tunmax/comedy1024/g' "$f"
                # Also hide/remove any overlay watermark divs
                sed -i 's/\(.*[Ww]atermark.*\)/<!-- removed watermark -->/g' "$f"
                sed -i 's/\(.*[Ll]ogo.*[Oo]pen[Cc]law.*\)/<!-- removed openclaw logo -->/g' "$f"
            fi
        done
    fi
done

# ---- 2. Search for watermark in noVNC launch scripts ----
# Some implementations use start.sh or similar scripts to inject HTML
find / -maxdepth 4 \( -name 'start.sh' -o -name 'start-novnc.sh' -o -name 'novnc.sh' \) 2>/dev/null | while read f; do
    if grep -li 'openclaw\|tunmax\|by b\.z\|watermark\|logo' "$f" 2>/dev/null; then
        echo "[rebrand] Found branding in script: $f"
        sed -i 's/tunmax\/OpenClaw_Computer/comedy1024\/hermes-agent-desktop/g' "$f"
        sed -i 's/OpenClaw_Computer/Hermes Agent Desktop/g' "$f"
        sed -i 's/OpenClaw Computer/Hermes Agent Desktop/g' "$f"
        sed -i 's/by b\.z/by comedy1024/g' "$f"
        sed -i 's/tunmax/comedy1024/g' "$f"
    fi
done

# ---- 3. Replace KDE desktop wallpaper ----
WALLPAPER_DIR="/usr/share/wallpapers"
CUSTOM_WALLPAPER="/opt/hermes-wallpaper.png"

if [ -f "$CUSTOM_WALLPAPER" ]; then
    echo "[rebrand] Installing Hermes wallpaper..."

    # Create wallpaper directory in KDE format
    mkdir -p "$WALLPAPER_DIR/hermes-agent-desktop/contents"

    # Copy PNG wallpaper
    cp "$CUSTOM_WALLPAPER" "$WALLPAPER_DIR/hermes-agent-desktop/contents/images.png"

    # Create metadata for KDE wallpaper
    cat > "$WALLPAPER_DIR/hermes-agent-desktop/metadata.json" << 'METADATA'
{
    "KPlugin": {
        "Authors": [{"Name": "comedy1024"}],
        "Id": "hermes-agent-desktop",
        "Name": "Hermes Agent Desktop",
        "Description": "Hermes Agent Desktop - AI Agent + Linux Desktop + Web UI",
        "Icon": "preferences-desktop-wallpaper"
    }
}
METADATA

    echo "[rebrand] Wallpaper installed to $WALLPAPER_DIR/hermes-agent-desktop/"
fi

# ---- 4. Configure KDE Plasma to use our wallpaper ----
PLASMA_RC="/root/.config/plasma-org.kde.plasma.desktop-appletsrc"

if [ -f "$PLASMA_RC" ]; then
    echo "[rebrand] Updating KDE Plasma wallpaper config..."

    # Find existing wallpaper setting and replace it
    # KDE uses "Image=file:///path/to/wallpaper" format
    sed -i 's|Image=.*|Image=file:///usr/share/wallpapers/hermes-agent-desktop|g' "$PLASMA_RC"
else
    echo "[rebrand] Creating KDE Plasma wallpaper config..."
    mkdir -p /root/.config
fi

# Also set wallpaper in kde global config
mkdir -p /root/.config
cat > /root/.config/plasma-wallpaper.conf << 'WALLCONF'
[Wallpaper]
defaultWallpaperTheme=hermes-agent-desktop
WALLCONF

# ---- 5. Remove any OpenClaw-specific desktop files ----
echo "[rebrand] Removing remaining OpenClaw desktop files..."
find /root/Desktop -name '*openclaw*' -o -name '*OpenClaw*' -o -name '*copaw*' 2>/dev/null | while read f; do
    echo "[rebrand] Removing: $f"
    rm -f "$f"
done

# Remove OpenClaw's "使用帮助.html" from desktop
if [ -f "/root/Desktop/使用帮助.html" ]; then
    echo "[rebrand] Removing OpenClaw help page: /root/Desktop/使用帮助.html"
    rm -f "/root/Desktop/使用帮助.html"
fi

# Remove any other Chinese-named help files from OpenClaw
find /root/Desktop -name '*使用帮助*' -o -name '*帮助*' 2>/dev/null | while read f; do
    echo "[rebrand] Removing: $f"
    rm -f "$f"
done

# Remove OpenClaw autostart entries
find /root/.config/autostart -name '*openclaw*' -o -name '*OpenClaw*' -o -name '*copaw*' 2>/dev/null | while read f; do
    echo "[rebrand] Removing autostart: $f"
    rm -f "$f"
done

# ---- 6. Search for and clean up any other branding files ----
echo "[rebrand] Searching for remaining brand references..."

# Check common locations for brand images/logos
BRAND_LOCATIONS="
/root/.openclaw
/root/.config/openclaw
/usr/share/pixmaps/openclaw*
/usr/share/icons/openclaw*
/usr/share/icons/*openclaw*
"

for loc in $BRAND_LOCATIONS; do
    for f in $loc; do
        if [ -e "$f" ]; then
            echo "[rebrand] Removing: $f"
            rm -rf "$f"
        fi
    done
done

# ---- 7. Search for text references in key config files ----
echo "[rebrand] Scanning config files for brand references..."
grep -rl 'openclaw\|tunmax' /root/.config/ 2>/dev/null | while read f; do
    if file "$f" | grep -qi 'text\|ascii'; then
        echo "[rebrand] Replacing brand text in: $f"
        sed -i 's/tunmax\/OpenClaw_Computer/comedy1024\/hermes-agent-desktop/g' "$f"
        sed -i 's/OpenClaw_Computer/Hermes Agent Desktop/g' "$f"
        sed -i 's/OpenClaw Computer/Hermes Agent Desktop/g' "$f"
        sed -i 's/openclaw_computer/hermes-agent-desktop/g' "$f"
        sed -i 's/tunmax/comedy1024/g' "$f"
    fi
done

echo "[rebrand] Rebranding complete!"
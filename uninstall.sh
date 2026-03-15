#!/bin/bash

# Touchscreen Driver Uninstaller

INSTALL_DIR="/usr/local/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.ymlaine.touchscreendriver.plist"
DOMAIN="gui/$(id -u)"

echo "======================================================="
echo "   Touchscreen Driver Uninstaller"
echo "======================================================="
echo ""

# Bootout LaunchAgent (macOS Tahoe)
if launchctl print "$DOMAIN/com.ymlaine.touchscreendriver" > /dev/null 2>&1; then
    echo "Booting out LaunchAgent..."
    launchctl bootout "$DOMAIN/com.ymlaine.touchscreendriver" 2>/dev/null || true
fi

# Stop any remaining processes
if pgrep -f TouchscreenDriver > /dev/null 2>&1; then
    echo "Stopping driver..."
    pkill -f TouchscreenDriver 2>/dev/null || true
fi

# Remove plist
if [ -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME" ]; then
    rm -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
    echo "LaunchAgent removed"
fi

# Remove binary
if [ -f "$INSTALL_DIR/TouchscreenDriver" ]; then
    echo "Removing binary..."
    sudo rm -f "$INSTALL_DIR/TouchscreenDriver"
    echo "Binary removed"
fi

# Clean up logs
rm -f /tmp/touchscreendriver.log

echo ""
echo "Uninstallation complete!"
echo ""
echo "Note: You may want to remove the permissions in System Settings:"
echo "   -> Privacy & Security -> Accessibility"
echo "   -> Privacy & Security -> Input Monitoring"

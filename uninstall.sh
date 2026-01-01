#!/bin/bash

# Touchscreen Driver Uninstaller

INSTALL_DIR="/usr/local/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.ymlaine.touchscreendriver.plist"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Touchscreen Driver Uninstaller                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Stop the driver
if pgrep -f TouchscreenDriver > /dev/null 2>&1; then
    echo "⏹️  Stopping driver..."
    pkill -f TouchscreenDriver 2>/dev/null || true
fi

# Unload LaunchAgent
if [ -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME" ]; then
    echo "⏹️  Unloading LaunchAgent..."
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
    rm -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
    echo "✅ LaunchAgent removed"
fi

# Remove binary
if [ -f "$INSTALL_DIR/TouchscreenDriver" ]; then
    echo "🗑️  Removing binary..."
    sudo rm -f "$INSTALL_DIR/TouchscreenDriver"
    echo "✅ Binary removed"
fi

# Clean up logs
rm -f /tmp/touchscreendriver.log

echo ""
echo "✅ Uninstallation complete!"
echo ""
echo "Note: You may want to remove the permissions in System Settings:"
echo "   → Privacy & Security → Accessibility"
echo "   → Privacy & Security → Input Monitoring"

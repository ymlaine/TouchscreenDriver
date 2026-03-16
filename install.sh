#!/bin/bash

# Touchscreen Driver Installer for Corsair Xeneon Edge
# This script installs the driver and configures it to run at login

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.ymlaine.touchscreendriver.plist"
DOMAIN="gui/$(id -u)"

echo "======================================================="
echo "   Touchscreen Driver Installer - Corsair Xeneon Edge"
echo "======================================================="
echo ""

# Check if already running
if pgrep -f TouchscreenDriver > /dev/null 2>&1; then
    echo "Stopping existing driver..."
    pkill -f TouchscreenDriver 2>/dev/null || true
    sleep 1
fi

# Bootout existing LaunchAgent if present (macOS Tahoe uses bootstrap/bootout)
if launchctl print "$DOMAIN/com.ymlaine.touchscreendriver" > /dev/null 2>&1; then
    echo "Booting out existing LaunchAgent..."
    launchctl bootout "$DOMAIN/com.ymlaine.touchscreendriver" 2>/dev/null || true
fi

# Compile the driver
echo "Compiling driver..."
cd "$SCRIPT_DIR"
swiftc TouchscreenDriver.swift -o TouchscreenDriver \
    -framework IOKit \
    -framework CoreFoundation \
    -framework CoreGraphics \
    -framework AppKit \
    -O

echo "Compilation successful"

# Install binary
echo "Installing to $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo cp TouchscreenDriver "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/TouchscreenDriver"

echo "Binary installed"

# Install LaunchAgent
echo "Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"
cp "$SCRIPT_DIR/$PLIST_NAME" "$LAUNCH_AGENTS_DIR/"

echo "LaunchAgent installed"

# Bootstrap LaunchAgent (macOS Tahoe)
echo "Bootstrapping LaunchAgent..."
launchctl bootstrap "$DOMAIN" "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo ""
echo "======================================================="
echo "Installation complete!"
echo ""
echo "The driver will now start automatically at login."
echo ""
echo "Commands:"
echo "  Start:   launchctl bootstrap $DOMAIN ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Stop:    launchctl bootout $DOMAIN/com.ymlaine.touchscreendriver"
echo "  Status:  pgrep -f TouchscreenDriver && echo 'Running' || echo 'Stopped'"
echo "  Logs:    tail -f /tmp/touchscreendriver.log"
echo ""
echo "First time? Grant permissions in System Settings:"
echo "   -> Privacy & Security -> Accessibility"
echo "   -> Privacy & Security -> Input Monitoring"
echo "======================================================="

#!/bin/bash

# Script de compilation et exécution pour le driver tactile

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Compilation de TouchscreenDriver.swift..."
swiftc TouchscreenDriver.swift -o TouchscreenDriver \
    -framework IOKit \
    -framework CoreFoundation \
    -framework CoreGraphics \
    -framework AppKit \
    -O

echo "✅ Compilation réussie!"
echo ""
echo "🚀 Lancement du driver..."
echo "   (Ctrl+C pour quitter)"
echo ""

./TouchscreenDriver

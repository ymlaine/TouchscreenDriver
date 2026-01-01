#!/bin/bash

# Script de compilation et exécution pour l'analyseur HID

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Compilation de HIDAnalyzer.swift..."
swiftc HIDAnalyzer.swift -o HIDAnalyzer \
    -framework IOKit \
    -framework CoreFoundation \
    -O

echo "✅ Compilation réussie!"
echo ""
echo "🚀 Lancement de l'analyseur..."
echo "   (Ctrl+C pour quitter)"
echo ""

./HIDAnalyzer

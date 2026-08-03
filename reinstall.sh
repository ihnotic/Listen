#!/bin/bash
# Rebuild, package, sign, and reinstall Listen.app.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building..."
"$SCRIPT_DIR/build.sh"

echo "==> Installing..."
pkill -x Listen 2>/dev/null || true
sleep 1

ditto "$SCRIPT_DIR/dist/Listen.app" /Applications/Listen.app
codesign --verify --deep --strict /Applications/Listen.app

echo "==> Launching..."
open /Applications/Listen.app
echo "==> Done!"

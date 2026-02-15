#!/bin/bash
# Rebuild, sign with stable cert, and reinstall Listen.app
# TCC permissions survive because the signing identity stays constant.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Building..."
swift build -c release

echo "==> Installing..."
pkill -x Listen 2>/dev/null || true
sleep 1

cp .build/release/Listen /Applications/Listen.app/Contents/MacOS/Listen
codesign --force --deep --sign "Listen Dev" \
    --entitlements /Applications/Listen.app/Contents/Listen.entitlements \
    /Applications/Listen.app

echo "==> Launching..."
open /Applications/Listen.app
echo "==> Done!"

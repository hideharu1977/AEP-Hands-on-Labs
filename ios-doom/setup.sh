#!/bin/bash
# setup.sh — Fetches doomgeneric engine sources and Freedoom WAD file.
# Run this script once before opening the Xcode project.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOOM_DIR="$SCRIPT_DIR/DoomIOS/DoomIOS"

echo "=== iOS Doom Setup ==="

# 1. Clone doomgeneric engine (shallow clone for speed)
# Re-clone if directory is missing OR incomplete (no .c files from a partial clone)
if [ ! -d "$DOOM_DIR/doomgeneric" ] || ! ls "$DOOM_DIR/doomgeneric"/*.c > /dev/null 2>&1; then
  echo "[1/2] Cloning doomgeneric engine..."
  rm -rf "$DOOM_DIR/doomgeneric"
  git clone --depth=1 https://github.com/ozkl/doomgeneric "$DOOM_DIR/doomgeneric"
  echo "      Done."
else
  echo "[1/2] doomgeneric already present, skipping."
fi

# 2. Download Freedoom Phase 1 WAD (free, BSD-licensed game content)
WAD="$DOOM_DIR/freedoom1.wad"
if [ ! -f "$WAD" ]; then
  echo "[2/2] Downloading Freedoom Phase 1 WAD..."
  RELEASE_URL="https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip"
  TMPZIP="/tmp/freedoom_$$.zip"
  curl -L --progress-bar "$RELEASE_URL" -o "$TMPZIP"
  unzip -j "$TMPZIP" "freedoom-0.13.0/freedoom1.wad" -d "$DOOM_DIR/"
  rm -f "$TMPZIP"
  echo "      Done. WAD saved to $WAD"
else
  echo "[2/2] freedoom1.wad already present, skipping."
fi

echo ""
echo "Setup complete!"
echo "Open DoomIOS/DoomIOS.xcodeproj in Xcode 15+ and build for iOS Simulator or device."

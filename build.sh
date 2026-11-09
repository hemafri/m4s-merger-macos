#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h}
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/M4S合并器.app"
BUILD_ARCH=$(uname -m)
if [[ "$BUILD_ARCH" != arm64 && "$BUILD_ARCH" != x86_64 ]]; then
  print -u2 "Unsupported architecture: $BUILD_ARCH"
  exit 1
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cd "$PROJECT_DIR"
swiftc -swift-version 5 -O -module-name M4SMerger \
  -target "$BUILD_ARCH-apple-macosx13.0" \
  -file-prefix-map "$PROJECT_DIR=." \
  -framework AppKit Main.swift -o "$APP_DIR/Contents/MacOS/M4SMerger"
cp merger.py AppIcon.icns "$APP_DIR/Contents/Resources/"
cp Info.plist "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
print "Built: $APP_DIR"

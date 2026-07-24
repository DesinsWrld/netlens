#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/NetLens.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

xcrun clang \
  -fobjc-arc \
  -O2 \
  -framework AppKit \
  -framework Network \
  "$ROOT_DIR/Sources/NetLens/main.m" \
  -o "$MACOS/NetLens"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$MACOS/NetLens"
codesign --force --sign - "$APP_DIR"

echo "Built $APP_DIR"

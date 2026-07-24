#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build_app.sh"
"$ROOT_DIR/dist/NetLensCore.app/Contents/MacOS/NetLensCore" --self-test
codesign --verify --deep --strict "$ROOT_DIR/dist/NetLensCore.app"
plutil -lint "$ROOT_DIR/dist/NetLensCore.app/Contents/Info.plist"
echo "All NetLens app checks passed"

#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
MACOS_DIR=${SCRIPT_DIR:h}
PROJECT_DIR=${MACOS_DIR:h}
RUNTIME_DIR="$MACOS_DIR/Runtime/macos-arm64"
BUILD_DIR="$MACOS_DIR/build"
APP_DIR="$BUILD_DIR/Traktor Stem Packager.app"

chmod +x "$SCRIPT_DIR/prepare-runtime.sh"

for component in node ffmpeg ffprobe; do
  if [[ ! -x "$RUNTIME_DIR/$component" ]]; then
    echo "Missing bundled runtime component: $RUNTIME_DIR/$component" >&2
    exit 1
  fi
done

cd "$MACOS_DIR"
swift build -c release --arch arm64

cd "$PROJECT_DIR"
npm ci --omit=dev

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Runtime" "$APP_DIR/Contents/Resources/Engine"
cp "$MACOS_DIR/.build/arm64-apple-macosx/release/TraktorStemPackager" "$APP_DIR/Contents/MacOS/TraktorStemPackager"
cp "$MACOS_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$RUNTIME_DIR/node" "$RUNTIME_DIR/ffmpeg" "$RUNTIME_DIR/ffprobe" "$APP_DIR/Contents/Resources/Runtime/"
cp -R "$PROJECT_DIR/src" "$PROJECT_DIR/vendor" "$PROJECT_DIR/node_modules" "$PROJECT_DIR/package.json" "$APP_DIR/Contents/Resources/Engine/"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/"
if [[ -f "$MACOS_DIR/FFMPEG-LICENSE.txt" ]]; then
  cp "$MACOS_DIR/FFMPEG-LICENSE.txt" "$APP_DIR/Contents/Resources/"
fi

chmod +x "$APP_DIR/Contents/MacOS/TraktorStemPackager" "$APP_DIR/Contents/Resources/Runtime/"*
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"

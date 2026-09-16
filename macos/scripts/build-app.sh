#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
MACOS_DIR=${SCRIPT_DIR:h}
PROJECT_DIR=${MACOS_DIR:h}
RUNTIME_DIR="$MACOS_DIR/Runtime/macos-arm64"
BUILD_DIR="$MACOS_DIR/build"
APP_DIR="$BUILD_DIR/Traktor Stem Packager.app"
ICON_SOURCE_B64="$MACOS_DIR/Resources/AppIcon-1024.jpg.base64"
ICON_SOURCE="$BUILD_DIR/AppIcon-1024.jpg"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

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

if [[ ! -f "$ICON_SOURCE_B64" ]]; then
  echo "Missing app icon source: $ICON_SOURCE_B64" >&2
  exit 1
fi

base64 -D -i "$ICON_SOURCE_B64" -o "$ICON_SOURCE"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 -s format png "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
if [[ -f "$MACOS_DIR/FFMPEG-LICENSE.txt" ]]; then
  cp "$MACOS_DIR/FFMPEG-LICENSE.txt" "$APP_DIR/Contents/Resources/"
fi

chmod +x "$APP_DIR/Contents/MacOS/TraktorStemPackager" "$APP_DIR/Contents/Resources/Runtime/"*
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"

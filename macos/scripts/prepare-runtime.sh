#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
MACOS_DIR=${SCRIPT_DIR:h}
RUNTIME_DIR="$MACOS_DIR/Runtime/macos-arm64"
DOWNLOAD_DIR="$MACOS_DIR/.runtime-downloads"

NODE_VERSION="22.23.2"
FFMPEG_STATIC_TAG="b6.1.1"

mkdir -p "$RUNTIME_DIR" "$DOWNLOAD_DIR"

NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-arm64.tar.gz"
NODE_BASE="https://nodejs.org/dist/v${NODE_VERSION}"
curl --fail --location --retry 3 "$NODE_BASE/$NODE_ARCHIVE" -o "$DOWNLOAD_DIR/$NODE_ARCHIVE"
curl --fail --location --retry 3 "$NODE_BASE/SHASUMS256.txt" -o "$DOWNLOAD_DIR/SHASUMS256.txt"
(
  cd "$DOWNLOAD_DIR"
  grep "  $NODE_ARCHIVE$" SHASUMS256.txt | shasum -a 256 -c -
)
tar -xzf "$DOWNLOAD_DIR/$NODE_ARCHIVE" -C "$DOWNLOAD_DIR"
cp "$DOWNLOAD_DIR/node-v${NODE_VERSION}-darwin-arm64/bin/node" "$RUNTIME_DIR/node"

FFMPEG_RELEASE="https://github.com/eugeneware/ffmpeg-static/releases/download/${FFMPEG_STATIC_TAG}"
for component in ffmpeg ffprobe; do
  curl --fail --location --retry 3 \
    "$FFMPEG_RELEASE/${component}-darwin-arm64" \
    -o "$RUNTIME_DIR/$component"
done
curl --fail --location --retry 3 \
  "$FFMPEG_RELEASE/darwin-arm64.LICENSE" \
  -o "$MACOS_DIR/FFMPEG-LICENSE.txt"

chmod +x "$RUNTIME_DIR/node" "$RUNTIME_DIR/ffmpeg" "$RUNTIME_DIR/ffprobe"

for component in node ffmpeg ffprobe; do
  if ! file "$RUNTIME_DIR/$component" | grep -q "arm64"; then
    echo "$component is not an arm64 macOS executable" >&2
    exit 1
  fi
done

echo "Prepared verified Node ${NODE_VERSION} and pinned FFmpeg ${FFMPEG_STATIC_TAG} runtime files."

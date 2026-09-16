# Third-party notices

The packaged application includes the following private runtime components.

## Node.js

Node.js is distributed under the MIT license with additional licenses for bundled dependencies. The build downloads the pinned official macOS arm64 release from nodejs.org. See <https://github.com/nodejs/node/blob/main/LICENSE>.

## FFmpeg and FFprobe

The build downloads the pinned macOS arm64 binaries published by `eugeneware/ffmpeg-static`. The matching license file is copied into the macOS build directory and must be included with distributed builds. See <https://github.com/eugeneware/ffmpeg-static>.

## stem-mp4

The vendored `stem-mp4` package is distributed under the MIT License. Its license is retained at `vendor/stem-mp4/LICENSE`.

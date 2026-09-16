# Native macOS application

This directory contains the SwiftUI front end for Traktor Stem Packager.

The distributable application is self-contained. Its app bundle includes the validated JavaScript packaging engine, a private Node runtime, FFmpeg, and FFprobe. Users do not install or operate those components separately.

## Current milestone

- Native SwiftUI interface
- Drag-and-drop or file-picker input for Master, Drums, Bass, Other, and Vocals
- Automatic compatibility and stem-sum validation
- Per-song Stem Master limiter decision
- Compressor disabled
- Save panel with `.stem.mp4` naming
- Progress, errors, and Finder reveal
- Apple Silicon build layout
- Traktor-inspired dark interface with exact default stem colors
- Editable stem display names
- Title, artist, album, genre, and year metadata
- JPEG/PNG artwork selection and embedding

## Build requirement

The final `.app` must be compiled on macOS with Xcode/Swift 5.10 or newer. Place arm64 macOS executables named `node`, `ffmpeg`, and `ffprobe` in `Runtime/macos-arm64`, then run `scripts/build-app.sh`. End users do not need Xcode or any separate runtime after the app has been built.

The release build must use redistributable runtime binaries, include their license notices, and be signed and notarized before distribution. The development script applies only an ad-hoc signature for local testing.

## Hosted beta build

The GitHub Actions workflow at `.github/workflows/build-macos.yml` runs the engine tests, downloads pinned arm64 Node/FFmpeg runtime files, builds the SwiftUI app, verifies the bundle and signature, and uploads a ZIP artifact. It is manually triggered from the repository's Actions page. The beta is ad-hoc signed for testing; public distribution still requires an Apple Developer certificate and notarization.

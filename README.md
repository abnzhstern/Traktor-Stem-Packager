# Traktor Stem Packager

This repository contains the packaging engine and native macOS app source. It accepts a stereo master plus Drums, Bass, Other, and Vocals, validates synchronization-critical properties, encodes each stream as 256 kbps AAC, and writes a five-track `.stem.mp4` with Native Instruments Stem metadata.

## Status

Version 0.4 adds the Traktor-inspired SwiftUI interface, drag-and-drop lanes, editable stem display names, exact Traktor Pro 4 colors, track metadata, cover artwork, and a collapsible validation report. The packaging handshake was already accepted by Traktor Pro 4. The distributable build bundles its encoder and engine so the user installs one `.app` and needs no separate software.

## Track order

1. Master
2. Drums
3. Bass
4. Other
5. Vocals

## Development use

```sh
npm install
node src/pack.mjs \
  --master "Master.aif" \
  --drums "Drums.aiff" \
  --bass "Bass.aiff" \
  --other "Other.aiff" \
  --vocals "Vocals.aiff" \
  --output "Song.stem.mp4" \
  --title "Song" \
  --artist "Artist"
```

Run `node src/inspect.mjs Song.stem.mp4` to verify that the output contains five AAC streams and the NI `stem` metadata atom.

## Compatibility policy

The five inputs must have the same sample rate, channel count, and duration. Stereo is required. WAV, AIFF, AAC/M4A, and MP3 inputs are accepted at 44.1, 48, 88.2, or 96 kHz. Source bit depth does not have to be 16-bit because inputs are encoded to AAC during packaging. The app does not resample, time-stretch, normalize, remix, or perform source separation. It measures the unprocessed four-stem sum and writes song-specific Stem Master metadata. Compression stays disabled; the Traktor limiter is enabled only when the measured sum exceeds the configured ceiling. 192 kHz is rejected until a Traktor-tested ALAC mode is available.

## Third-party components

The prototype uses `stem-mp4` under the MIT License and FFmpeg for development encoding. The distributable macOS build will include the relevant notices and a legally redistributable encoder build.

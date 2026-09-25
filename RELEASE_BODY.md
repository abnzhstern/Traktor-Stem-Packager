# Traktor Stem Packager 1.0.0

The first stable public release of Traktor Stem Packager, a free and open-source macOS utility from LuckyStar Productions.

It packages a stereo master and four matching stems that you already created or received. It is not a stem-separation application.

## Two workflows

- **AAC Stem File** creates one portable, shareable 320 kbps AAC `.stem.mp4` that can be imported directly into Traktor.
- **Lossless Traktor Installation** packages supported PCM WAV/AIFF sources as ALAC and links them to the exact analyzed stereo master already in Traktor, preserving that track's cues, beat grid, loops, play history, and other Traktor metadata.

Supported lossless profiles are matched stereo files at 16-bit/44.1 kHz or 24-bit/48 kHz. Every packaged lossless stream is decoded and PCM SHA-256 verified against its source before installation.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- Traktor Pro 4

## Installation

Download `Traktor-Stem-Packager-1.0.0-macOS.zip`, unzip it, and follow the included README. Keep the app and installer command together during installation.

This free build is ad-hoc signed rather than Apple-notarized. Some Macs require the documented one-time Terminal installation method. The installer does not disable Gatekeeper or change system-wide security settings.

## Important

Back up important music libraries as part of your normal workflow. Lossless installation creates a timestamped backup of `collection.nml` before changing it and retains a backup when replacing an existing linked Stem file.

TRAKTOR is a trademark of Native Instruments GmbH. This independent project is not affiliated with, sponsored by, or endorsed by Native Instruments.

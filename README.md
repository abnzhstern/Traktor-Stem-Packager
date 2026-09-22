# Traktor Stem Packager

A free, open-source macOS utility that packages a stereo master and four matching stems into a Native Instruments-compatible `.stem.mp4` file for Traktor Pro 4.

![Traktor Stem Packager icon](macos/Resources/AppIcon-1024.png)

## Download

Download the latest macOS installer from the [Releases page](https://github.com/abnzhstern/Traktor-Stem-Packager/releases/latest).

The current build supports **Apple Silicon Macs** running **macOS 14 or newer**. It is free and open source, but it is not signed or notarized through Apple's paid Developer Program.

## What it does

- Accepts a stereo master plus Drums, Bass, Other, and Vocals stems
- Validates sample rate, channel count, duration, and synchronization-critical properties
- Reads title, artist, album, release date, producer, label, genre, and artwork from the stereo master
- Lets you edit metadata and stem display names before packaging
- Portable mode encodes five Apple AudioToolbox AAC streams at 320 kbps CBR and writes Native Instruments Stem metadata
- Experimental lossless mode accepts only uncompressed PCM WAV/AIFF sources in a tested profile (16-bit/44.1 kHz or 24-bit/48 kHz), stores them as ALAC in Traktor's configured Stems folder, and safely links them to an existing track in `collection.nml`
- Decodes and SHA-256 verifies every packaged lossless stream against its source before installation
- Can ask Traktor to save and quit normally before installation, then relaunch it afterward
- Measures the unprocessed four-stem sum and enables limiter protection only when needed
- Creates a Traktor-compatible `.stem.mp4`

## Required track order

1. Master
2. Drums
3. Bass
4. Other
5. Vocals

All five inputs must be stereo and must have matching sample rates and durations. WAV, AIFF, AAC/M4A, and MP3 inputs are supported at 44.1, 48, 88.2, or 96 kHz. The app does not perform source separation, resampling, time-stretching, normalization, or remixing.

## Installation

1. Download and unzip the installer from the Releases page.
2. Keep `Traktor Stem Packager.app` and `Install Traktor Stem Packager.command` together.
3. Control-click or right-click the installer command and choose **Open**.
4. If macOS blocks it, open Terminal, type `zsh ` with a trailing space, drag the installer command into Terminal, and press Return.

The installer places the app in Applications, clears quarantine attributes from this app only, repairs executable permissions, creates a local ad-hoc signature, verifies the app, and launches it. It does not disable Gatekeeper or alter system-wide security settings.

To update, run the newer installer without deleting the existing app first. It installs the update in the same Applications location and moves the previous version to the Trash as a recoverable backup.

The app checks GitHub Releases at most once every 24 hours and displays a notice when a newer version is available. You can also choose **Check for Updates…** from the app menu. Automatic connection failures are silent, no audio or metadata is uploaded, and downloads always use the permanent [latest-release link](https://github.com/abnzhstern/Traktor-Stem-Packager/releases/latest).

Because the build is not Apple-notarized, macOS behavior may vary by version and security software. Terminal is needed only for installation when macOS blocks the normal right-click method.

## Build from source

Requirements:

- Apple Silicon Mac
- macOS 14 or newer
- Xcode/Swift 5.10 or newer
- Node.js 18 or newer

```sh
npm install
npm test
macos/scripts/prepare-runtime.sh
macos/scripts/build-app.sh
```

The completed app is written to `macos/build/Traktor Stem Packager.app`.

Portable AAC remains the shareable standalone `.stem.mp4` option. Lossless ALAC is an experimental linked mode: the original master must already be imported and analyzed in Traktor Pro 4, and the app creates a timestamped collection backup before making the link. If Traktor is open, the app requests a normal save-and-quit before installation and relaunches it afterward.

The command-line packaging engine can also be run directly:

```sh
node src/pack.mjs \
  --master "Master.aif" \
  --drums "Drums.aiff" \
  --bass "Bass.aiff" \
  --other "Other.aiff" \
  --vocals "Vocals.aiff" \
  --output "Song.stem.mp4"
```

## Privacy

Audio files are processed locally on the Mac. The application does not upload audio or metadata to an external service.

## License and third-party software

This project is released under the [MIT License](LICENSE). Bundled and vendored components retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Trademark disclaimer

TRAKTOR is a trademark of Native Instruments GmbH. This independent project is not affiliated with, sponsored by, or endorsed by Native Instruments.

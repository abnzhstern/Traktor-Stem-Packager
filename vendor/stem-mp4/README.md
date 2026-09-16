# stem-mp4

[![Tests](https://github.com/monteslu/stem-mp4/actions/workflows/test.yml/badge.svg)](https://github.com/monteslu/stem-mp4/actions/workflows/test.yml)
[![npm version](https://badge.fury.io/js/stem-mp4.svg)](https://www.npmjs.com/package/stem-mp4)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Read and write multi-track Stem MP4 (`.stem.mp4`) files with karaoke extensions.

**Perfect for karaoke applications** - Store backing tracks and synchronized lyrics in a single file format compatible with DJ software like Traktor and Mixxx.

**▶️ [Live Demo](https://stemsplayer.netlify.app/)** — load a `.stem.mp4` file in the browser and mute/solo individual stems. Source: [m4aplayer](https://github.com/monteslu/m4aplayer) (React + Vite, uses `stem-mp4/extractor`).

## Features

- 🎵 **Multi-track Audio** - Read/write MP4 files with 5 tracks (master + 4 stems)
- 🎤 **Karaoke Lyrics** - Synchronized lyrics with word-level timing
- 🎹 **Musical Metadata** - Key detection, BPM, vocal pitch tracking
- 🎛️ **NI Stems Compatible** - Works with Traktor, Mixxx, and other DJ software
- 🔧 **100% Pure JS** - Read AND write in pure JS, no FFmpeg or native deps
- 🎚️ **Codec-agnostic** - You supply pre-encoded MP4 tracks; the lib only does the container (AAC is the NI Stems standard; ALAC/others mux fine too)
- 📝 **iTunes Compatible** - Standard metadata atoms (title, artist, album)
- 🌐 **Fully Isomorphic** - Reader AND writer work in both Node.js and browsers

## Installation

```bash
npm install stem-mp4
```

**Requirements:**
- Node.js >= 18.0.0

## File Format

This library works with `.stem.mp4` or `.stem.m4a` files that follow the [NI Stems specification](https://www.native-instruments.com/en/specials/stems/) with karaoke extensions.

> **Note:** The official NI spec uses `.stem.mp4`, but `.stem.m4a` is equally valid since both are MP4 containers. Use `.stem.mp4` for maximum DJ software compatibility (Traktor, etc.), or `.stem.m4a` if targeting audio applications.

### Audio Tracks

| Track | Content | Purpose |
|-------|---------|---------|
| 0 | Master | Full mix (plays in normal audio players) |
| 1 | Drums | Rhythm, percussion |
| 2 | Bass | Low-end, basslines |
| 3 | Other | Melody, instruments, synths |
| 4 | Vocals | Vocals (mute for karaoke) |

### Metadata Structure

The format uses two metadata locations:

1. **`stem` atom** (`moov/udta/stem`) - NI Stems metadata for DJ software compatibility
2. **`kara` atom** (`moov/udta/meta/ilst/----:com.stems:kara`) - Karaoke lyrics and timing

This dual approach means files work in both DJ software and karaoke applications.

## Quick Start

### Extract Audio Tracks

The Extractor works with binary data - you handle the I/O, the library handles the extraction. Returns each track as a standalone MP4/M4A buffer.

**Accepted input types:**
- `Uint8Array` - works everywhere
- `ArrayBuffer` - works everywhere (e.g., from `fetch`)
- Node.js `Buffer` - works in Node.js only

#### Node.js Usage

```javascript
import * as Extractor from 'stem-mp4/extractor';
import fs from 'fs/promises';

// Read the file yourself
const fileData = await fs.readFile('song.stem.mp4');

// Extract tracks (synchronous, returns Uint8Array)
const trackBuffer = Extractor.extractTrack(fileData, 0);
const allTracks = Extractor.extractAllTracks(fileData);
const info = Extractor.getTrackInfo(fileData);
const count = Extractor.getTrackCount(fileData);
```

#### Browser Usage

```javascript
import * as Extractor from 'stem-mp4/extractor';

// Fetch the file yourself
const response = await fetch('song.stem.mp4');
const arrayBuffer = await response.arrayBuffer();

// Extract tracks (synchronous, returns Uint8Array)
const trackBuffer = Extractor.extractTrack(arrayBuffer, 0);
const allTracks = Extractor.extractAllTracks(arrayBuffer);
```

#### Browser with Web Audio API

```javascript
import * as Extractor from 'stem-mp4/extractor';

// Fetch stems file
const response = await fetch('song.stem.mp4');
const arrayBuffer = await response.arrayBuffer();

// Extract all tracks as separate M4A buffers
const tracks = Extractor.extractAllTracks(arrayBuffer);

// Decode each track with Web Audio API
const audioContext = new AudioContext();
const audioBuffers = await Promise.all(
  tracks.map(track => audioContext.decodeAudioData(track.buffer))
);

// Now you have 5 AudioBuffers: master, drums, bass, other, vocals
```

### Read Metadata and Lyrics

```javascript
import { StemMp4Reader, Atoms } from 'stem-mp4';

// Full file load
const data = await StemMp4Reader.load('song.stem.mp4');

console.log(data.metadata.title);     // "Song Title"
console.log(data.metadata.artist);    // "Artist Name"
console.log(data.metadata.key);       // "Am"
console.log(data.metadata.duration);  // 180.5 (seconds)

// Access lyrics with timing
console.log(data.lyrics);
// [
//   { start: 0.5, end: 2.0, text: 'First line', words: { timings: [[0, 0.3], [0.4, 0.8]] } },
//   { start: 2.5, end: 4.0, text: 'Second line' }
// ]

// Or read atoms directly
const stems = await Atoms.readNiStemsMetadata('song.stem.mp4');
// { version: 1, mastering_dsp: {...}, stems: [{name: 'drums', color: '#FF0000'}, ...] }

const kara = await Atoms.readKaraAtom('song.stem.mp4');
// { timing: {...}, lines: [...], singers: {...} }
```

### Write Metadata

```javascript
import { Atoms } from 'stem-mp4';

// Add NI Stems metadata (for DJ software)
await Atoms.addNiStemsMetadata('song.stem.mp4', ['drums', 'bass', 'other', 'vocals']);

// Add karaoke data
await Atoms.writeKaraAtom('song.stem.mp4', {
  timing: { offset_sec: 0 },
  lines: [
    {
      start: 0.5,
      end: 2.0,
      text: 'Hello world',
      words: { timings: [[0, 0.4], [0.5, 1.0]] }  // Word-level timing
    }
  ]
});

// Add standard metadata
await Atoms.addStandardMetadata('song.stem.mp4', {
  title: 'Song Title',
  artist: 'Artist Name',
  album: 'Album Name',
  year: 2024,
  genre: 'Rock',
  tempo: 120
});

// Add musical key
await Atoms.addMusicalKey('song.stem.mp4', 'Am');
```

### Create New Stem Files (Pure JS — No FFmpeg)

The Writer is pure JS: it muxes the multi-track container and writes the karaoke/
metadata atoms. **You supply the audio already encoded as MP4-wrapped tracks** —
encoding is intentionally the caller's job, so the library stays dependency-free
and runs identically in Node and the browser.

> **Input contract:** each track is **AAC (or ALAC, etc.) samples inside an MP4/
> M4A container** — a `Uint8Array`/`ArrayBuffer`/`Buffer`. NOT a raw ADTS `.aac`
> elementary stream (no `moov`/sample table → can't be muxed). The writer copies
> each input's sample table + codec description verbatim, so it's codec-agnostic;
> just make sure all tracks share the same sample rate and encoder priming.
> Produce the tracks however you like — `ffmpeg -c:a aac out.m4a` on a server,
> [ffmpeg.wasm](https://github.com/ffmpegwasm/ffmpeg.wasm) or WebCodecs in a
> browser.

```javascript
import { StemMp4Writer } from 'stem-mp4';

await StemMp4Writer.write({
  outputPath: 'output.stem.mp4', // Node only; omit in the browser and use the returned `data`

  // Pre-encoded single-track AAC-in-MP4 (Uint8Array / ArrayBuffer / Buffer)
  stemsAac: {
    vocals: vocalsAac,
    drums: drumsAac,
    bass: bassAac,
    other: otherAac,
  },

  // The full mix = NI-Stems master track (also pre-encoded MP4)
  mixdownAac,

  // Metadata
  metadata: {
    title: 'Song Title',
    artist: 'Artist Name',
    key: 'Am',
    tempo: 120,
  },

  // Karaoke lyrics
  lyricsData: {
    lines: [
      { start: 0.5, end: 2.0, text: 'First line of lyrics' },
      { start: 2.5, end: 4.0, text: 'Second line of lyrics' },
    ],
  },

  // AAC priming delay your encoder introduced (default 1105 = ffmpeg's native aac).
  // Used to align lyric timing — set correctly if you use a different encoder.
  encoderDelaySamples: 1105,
});

// Returns { success, data: Uint8Array, outputFile?, fileSizeBytes, profile }.
// In the browser, offer `data` as a download — no filesystem needed.
```

## Command Line Interface

```bash
# Inspect file structure
npx stem-mp4 song.stem.mp4

# Show only metadata
npx stem-mp4 song.stem.mp4 --metadata

# Show only lyrics
npx stem-mp4 song.stem.mp4 --lyrics

# Show MP4 atom tree
npx stem-mp4 song.stem.mp4 --atoms
```

## API Reference

### Extractor

```javascript
import * as Extractor from 'stem-mp4/extractor';
```

All functions are synchronous. Input accepts `Uint8Array`, `ArrayBuffer`, or Node.js `Buffer`:

```javascript
Extractor.extractTrack(data, trackIndex) → Uint8Array
Extractor.extractAllTracks(data) → Uint8Array[]
Extractor.getTrackCount(data) → number
Extractor.getTrackInfo(data) → TrackInfo[]
```

### Atoms

```javascript
import { Atoms } from 'stem-mp4';

// NI Stems metadata
await Atoms.readNiStemsMetadata(filePath) → Object
await Atoms.addNiStemsMetadata(filePath, stemNames) → void

// Karaoke data
await Atoms.readKaraAtom(filePath) → Object
await Atoms.writeKaraAtom(filePath, karaData) → void

// Standard metadata
await Atoms.addStandardMetadata(filePath, metadata) → void
await Atoms.addMusicalKey(filePath, key) → void

// Advanced features
await Atoms.writeVpchAtom(filePath, pitchData) → void  // Vocal pitch
await Atoms.writeKonsAtom(filePath, onsetsArray) → void // Beat onsets
await Atoms.dumpAtomTree(filePath) → Object[]
```

### Reader

```javascript
import { StemMp4Reader } from 'stem-mp4';

const data = await StemMp4Reader.load(filePath);
// {
//   metadata: { title, artist, album, duration, key, tempo, genre, year },
//   lyrics: [{ start, end, text, words? }],
//   features: { vocalPitch, onsets },
//   audio: { sources, timing, profile }
// }
```

### Writer (Pure JS)

```javascript
import { StemMp4Writer } from 'stem-mp4';

const { data } = await StemMp4Writer.write({
  outputPath,                                  // Node only; omit in browser, use returned `data`
  stemsAac: { vocals, drums, bass, other },    // pre-encoded MP4-wrapped tracks (Uint8Array/ArrayBuffer/Buffer)
  mixdownAac,                                  // the master/full-mix track
  metadata: { title, artist, album, key, tempo, genre, year },
  lyricsData: { lines },
  profile: 'STEMS-4',                          // 'STEMS-4' (default) | 'STEMS-2' (music + vocals)
  encoderDelaySamples: 1105,                   // your encoder's AAC priming (default = ffmpeg native aac)
  sampleRate: 44100,
});
```

## Format Compatibility

**DJ Software (Full Stem Support):**
- Native Instruments Traktor
- Mixxx

**Audio Players (Master Track Only):**
- Any M4A/AAC compatible player

**Karaoke Applications:**
- [Loukai](https://github.com/monteslu/loukai) - Full karaoke player with stem control

## Demos & Examples

- **[Live Demo](https://stemsplayer.netlify.app/)** - In-browser stem player (load a file, mute/solo stems, waveform seek)
- **[m4aplayer](https://github.com/monteslu/m4aplayer)** - Source code for the demo above (React + Vite + Web Audio API)
- **[Loukai](https://loukai.com)** - Production karaoke app built on this format ([format docs](https://loukai.com/format.html))

## Testing

```bash
npm test           # Run tests
npm run test:coverage  # With coverage
npm run lint       # Linting
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Created by [Luis Montes](https://github.com/monteslu) as part of the [Loukai](https://github.com/monteslu/loukai) karaoke project.

See the [Loukai M4A Format Specification](https://github.com/monteslu/loukai/blob/main/docs/m4a_format.md) for complete format details.

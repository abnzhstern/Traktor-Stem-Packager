/**
 * stem-mp4
 * Read and write multi-track Stem MP4 (.stem.mp4) files with karaoke extensions
 */

import StemMp4Reader from './reader.js';
import StemMp4Writer from './writer.js';
import * as Atoms from './atoms.js';
import * as WebVTT from './webvtt.js';
import * as Extractor from './extractor.js';

export { StemMp4Reader, StemMp4Writer, Atoms, WebVTT, Extractor };

export default {
  Reader: StemMp4Reader,
  Writer: StemMp4Writer,
  Atoms,
  WebVTT,
  Extractor,
};

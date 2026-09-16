#!/usr/bin/env node
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { Atoms } from 'stem-mp4';

const execFileAsync = promisify(execFile);
const file = process.argv[2];
if (!file) throw new Error('Usage: node src/inspect.mjs FILE.stem.mp4');

const { stdout } = await execFileAsync(process.env.STEM_PACKAGER_FFPROBE || 'ffprobe', [
  '-v', 'error', '-show_entries', 'stream=index,codec_name,codec_type,sample_rate,channels,duration', '-of', 'json', file,
]);
const probe = JSON.parse(stdout);
const niMetadata = await Atoms.readNiStemsMetadata(file);

console.log(JSON.stringify({ streams: probe.streams, niMetadata }, null, 2));

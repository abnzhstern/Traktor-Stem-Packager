import { execFile } from 'node:child_process';
import { copyFile, mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, join, normalize, resolve } from 'node:path';
import { promisify } from 'node:util';
import * as Atoms from '../vendor/stem-mp4/src/atoms.js';

const execFileAsync = promisify(execFile);
const STEM_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
const STEM_COLORS = ['#FD6C38', '#D232F4', '#00FFAC', '#45DAFD'];

function rotateLeft(value, bits) {
  return ((value << bits) | (value >>> (32 - bits))) >>> 0;
}

const shifts = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];
const constants = Array.from({ length: 64 }, (_, index) =>
  Math.floor(Math.abs(Math.sin(index + 1)) * 0x100000000) >>> 0,
);

function md5Transform(state, block) {
  const words = Array.from({ length: 16 }, (_, index) => block.readUInt32LE(index * 4));
  let [a, b, c, d] = state;
  for (let i = 0; i < 64; i++) {
    let f;
    let g;
    if (i < 16) {
      f = (b & c) | (~b & d);
      g = i;
    } else if (i < 32) {
      f = (d & b) | (~d & c);
      g = (5 * i + 1) % 16;
    } else if (i < 48) {
      f = b ^ c ^ d;
      g = (3 * i + 5) % 16;
    } else {
      f = c ^ (b | ~d);
      g = (7 * i) % 16;
    }
    const next = (b + rotateLeft((a + f + constants[i] + words[g]) >>> 0, shifts[i])) >>> 0;
    [a, b, c, d] = [d, next, b, c];
  }
  state[0] = (state[0] + a) >>> 0;
  state[1] = (state[1] + b) >>> 0;
  state[2] = (state[2] + c) >>> 0;
  state[3] = (state[3] + d) >>> 0;
}

export function traktorHashWords(audioId) {
  const bytes = Buffer.from(audioId, 'base64');
  if (bytes.length !== 256) throw new Error(`Traktor AUDIO_ID must decode to 256 bytes; found ${bytes.length}.`);
  const state = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476];
  for (let offset = 0; offset < 256; offset += 64) md5Transform(state, bytes.subarray(offset, offset + 64));
  md5Transform(state, Buffer.alloc(64));
  return state;
}

export function nativeStemRelativePath(audioId) {
  const words = traktorHashWords(audioId);
  const shard = String(words[0] & 0x7f).padStart(3, '0');
  let stemName = '';
  for (const word of words) {
    for (let shift = 0; shift <= 30; shift += 5) stemName += STEM_ALPHABET[(word >>> shift) & 0x1f];
  }
  return join(shard, `${stemName}.stem.mp4`);
}

function decodeXml(value) {
  return value
    .replaceAll('&quot;', '"').replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');
}

function attributes(tag) {
  const result = {};
  for (const match of tag.matchAll(/([A-Za-z0-9_:-]+)="([^"]*)"/g)) result[match[1]] = decodeXml(match[2]);
  return result;
}

function normalizedPath(path) {
  return normalize(resolve(path)).normalize('NFC');
}

function locationCandidates(location) {
  const attrs = attributes(location);
  if (!attrs.DIR || !attrs.FILE) return [];
  const directory = attrs.DIR.replaceAll('/:', '/').replace(/:$/, '');
  const direct = normalizedPath(join(directory, attrs.FILE));
  const candidates = [direct];
  if (attrs.VOLUME && !direct.startsWith('/Users/')) {
    candidates.push(normalizedPath(join('/Volumes', attrs.VOLUME, directory, attrs.FILE)));
  }
  return candidates;
}

export function findCollectionEntry(collectionText, masterPath) {
  const inspection = inspectCollectionEntry(collectionText, masterPath);
  if (!inspection.found) {
    throw new Error('The selected master is not in this Traktor collection. Import and analyze that exact master file first.');
  }
  if (!inspection.hasAudioId) {
    throw new Error('The matching Traktor track has no AUDIO_ID. Analyze the original track in Traktor first.');
  }
  return inspection.entry;
}

export function inspectCollectionEntry(collectionText, masterPath) {
  const target = normalizedPath(masterPath);
  for (const match of collectionText.matchAll(/<ENTRY\b[\s\S]*?<\/ENTRY>/g)) {
    const entryText = match[0];
    const location = entryText.match(/<LOCATION\b[^>]*\/?\s*>/)?.[0];
    if (!location || !locationCandidates(location).includes(target)) continue;
    const entryTag = entryText.match(/^<ENTRY\b[^>]*>/)?.[0];
    const audioId = entryTag ? attributes(entryTag).AUDIO_ID : null;
    const entry = { audioId, entryText, index: match.index };
    return {
      ready: Boolean(audioId),
      found: true,
      hasAudioId: Boolean(audioId),
      message: audioId
        ? 'Master found and analyzed in the selected Traktor collection.'
        : 'Master found, but Traktor has not assigned an AUDIO_ID. Analyze it in Traktor first.',
      entry,
    };
  }
  return {
    ready: false,
    found: false,
    hasAudioId: false,
    message: 'This exact master is not in the selected Traktor collection. Import and analyze it in Traktor first.',
    entry: null,
  };
}

export function markEntryHasLinkedStems(collectionText, foundEntry) {
  let updatedEntry = foundEntry.entryText;
  const infoTag = updatedEntry.match(/<INFO\b[^>]*\/?\s*>/)?.[0];
  if (infoTag) {
    const infoAttributes = attributes(infoTag);
    const flags = Number.parseInt(infoAttributes.FLAGS || '0', 10);
    const updatedFlags = Number.isFinite(flags) ? flags | 64 : 64;
    const replacement = /\bFLAGS="[^"]*"/.test(infoTag)
      ? infoTag.replace(/\bFLAGS="[^"]*"/, `FLAGS="${updatedFlags}"`)
      : infoTag.replace(/\s*\/?\s*>$/, ` FLAGS="${updatedFlags}"${infoTag.includes('/>') ? '/>' : '>'}`);
    updatedEntry = updatedEntry.replace(infoTag, replacement);
  } else {
    updatedEntry = updatedEntry.replace('</ENTRY>', '<INFO FLAGS="64"/>\n</ENTRY>');
  }
  return collectionText.slice(0, foundEntry.index) + updatedEntry +
    collectionText.slice(foundEntry.index + foundEntry.entryText.length);
}

function patchNativeTrackHeaders(bytes) {
  const data = Buffer.from(bytes);
  let index = data.indexOf('tkhd');
  while (index !== -1) {
    const boxStart = index - 4;
    const version = data[boxStart + 8];
    const alternateGroupOffset = boxStart + (version === 1 ? 54 : 42);
    data.writeUInt16BE(0, alternateGroupOffset);
    index = data.indexOf('tkhd', index + 4);
  }
  return data;
}

async function traktorIsRunning() {
  try {
    await execFileAsync('/usr/bin/pgrep', ['-x', 'Traktor Pro 4']);
    return true;
  } catch (error) {
    if (error.code === 1) return false;
    return false;
  }
}

function timestamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

async function decodedPcmSha256(file, streamIndex, ffmpeg) {
  const { stdout } = await execFileAsync(ffmpeg, [
    '-hide_banner', '-loglevel', 'error',
    '-i', file,
    '-map', `0:a:${streamIndex}`,
    '-vn', '-sn', '-dn',
    '-c:a', 'pcm_s16le',
    '-f', 'hash', '-hash', 'sha256', '-'
  ], { maxBuffer: 1024 * 1024 });
  const match = stdout.match(/SHA256=([a-f0-9]{64})/i);
  if (!match) throw new Error(`Could not calculate decoded PCM hash for ${file}.`);
  return match[1].toLowerCase();
}

export async function verifyNativePcmRoundTrip({ inputs, packagedFile, ffmpeg }) {
  const roles = ['master', 'drums', 'bass', 'other', 'vocals'];
  const verified = [];
  for (let index = 0; index < roles.length; index++) {
    const role = roles[index];
    const [sourceHash, packagedHash] = await Promise.all([
      decodedPcmSha256(inputs[role], 0, ffmpeg),
      decodedPcmSha256(packagedFile, index, ffmpeg),
    ]);
    if (sourceHash !== packagedHash) {
      throw new Error(`Lossless verification failed for ${role}: decoded PCM does not match the source.`);
    }
    verified.push({ role, sha256: sourceHash });
  }
  return verified;
}

export async function createNativeLinkedAlac({
  inputs, collectionPath, stemsDirectory, temporaryDirectory, ffmpeg, ffprobe, masteringDsp, stemNames,
}) {
  if (await traktorIsRunning()) throw new Error('Quit Traktor Pro 4 before installing linked stems.');
  const collection = await readFile(collectionPath, 'utf8');
  const foundEntry = findCollectionEntry(collection, inputs.master);
  const relativePath = nativeStemRelativePath(foundEntry.audioId);
  const destination = join(stemsDirectory, relativePath);
  const baseFile = join(temporaryDirectory, 'native-alac-base.mp4');
  const finalFile = join(temporaryDirectory, 'native-alac-final.mp4');

  const roles = ['master', 'drums', 'bass', 'other', 'vocals'];
  const args = ['-hide_banner', '-loglevel', 'error', '-y'];
  for (const role of roles) args.push('-i', inputs[role]);
  for (let index = 0; index < roles.length; index++) args.push('-map', `${index}:a:0`);
  args.push('-map_metadata', '-1', '-c:a', 'alac', '-sample_fmt', 's16p', '-ar', '44100');
  for (let index = 0; index < roles.length; index++) args.push(`-disposition:a:${index}`, 'default');
  args.push('-brand', 'mp42', '-f', 'mp4', baseFile);
  await execFileAsync(ffmpeg, args, { maxBuffer: 16 * 1024 * 1024 });

  let data = await readFile(baseFile);
  data = await Atoms.addNiStemsMetadataBuffer(data, stemNames, masteringDsp);
  data = patchNativeTrackHeaders(data);
  await writeFile(finalFile, data);

  const { stdout } = await execFileAsync(ffprobe, [
    '-v', 'error', '-select_streams', 'a', '-show_entries',
    'stream=codec_name,sample_rate,channels,duration_ts', '-of', 'json', finalFile,
  ]);
  const streams = JSON.parse(stdout).streams || [];
  if (streams.length !== 5 || streams.some((stream) =>
    stream.codec_name !== 'alac' || Number(stream.sample_rate) !== 44100 || Number(stream.channels) !== 2)) {
    throw new Error('Lossless verification failed before installation.');
  }

  const verifiedPcm = await verifyNativePcmRoundTrip({ inputs, packagedFile: finalFile, ffmpeg });

  const stamp = timestamp();
  const collectionBackup = `${collectionPath}.TraktorStemPackager-${stamp}.bak`;
  await copyFile(collectionPath, collectionBackup);
  await mkdir(dirname(destination), { recursive: true });
  let stemBackup = null;
  try {
    try {
      stemBackup = `${destination}.TraktorStemPackager-${stamp}.bak`;
      await copyFile(destination, stemBackup);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      stemBackup = null;
    }
    const stagedStem = `${destination}.tmp-${process.pid}`;
    await copyFile(finalFile, stagedStem);
    await rename(stagedStem, destination);

    const updatedCollection = markEntryHasLinkedStems(collection, foundEntry);
    const stagedCollection = `${collectionPath}.tmp-${process.pid}`;
    await writeFile(stagedCollection, updatedCollection, 'utf8');
    await rename(stagedCollection, collectionPath);
  } catch (error) {
    if (stemBackup) await copyFile(stemBackup, destination).catch(() => {});
    else await rm(destination, { force: true }).catch(() => {});
    await copyFile(collectionBackup, collectionPath).catch(() => {});
    throw error;
  }

  return {
    destination,
    collectionBackup,
    stemBackup,
    relativePath,
    verification: 'Decoded PCM is bit-for-bit identical to all five sources.',
    verifiedStreams: verifiedPcm.length,
  };
}

export const nativeStemColors = STEM_COLORS;

#!/usr/bin/env node
import { readFile, rm } from 'node:fs/promises';
import { basename, extname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { mkdtemp } from 'node:fs/promises';
import { StemMp4Writer } from 'stem-mp4';
import { analyzeStemSum, createProtectiveDsp, encodeAac, probeAudio, validateSet } from './media.mjs';
import { readMasterMetadata } from './metadata.mjs';
import { createNativeLinkedAlac } from './native-link.mjs';

function usage() {
  console.error('Usage: node src/pack.mjs --master FILE --drums FILE --bass FILE --other FILE --vocals FILE [--output FILE] [--mode portable-aac|native-alac] [--collection FILE --stems-dir DIR] [--validate-only true] [--title TITLE] [--artist ARTIST] [--album ALBUM] [--release-date DATE] [--producer PRODUCER] [--label LABEL] [--genre GENRE] [--drums-name NAME] [--bass-name NAME] [--other-name NAME] [--vocals-name NAME]');
}

function parseArgs(argv) {
  const options = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    if (!key?.startsWith('--') || argv[i + 1] == null) throw new Error(`Invalid argument: ${key ?? ''}`);
    options[key.slice(2)] = argv[i + 1];
  }
  return options;
}

const trackNames = ['master', 'drums', 'bass', 'other', 'vocals'];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const mode = args.mode || 'portable-aac';
  const validateOnly = args['validate-only'] === 'true';
  if (!['portable-aac', 'native-alac'].includes(mode)) throw new Error(`Unknown packaging mode: ${mode}`);
  const required = validateOnly
    ? trackNames
    : mode === 'native-alac'
      ? [...trackNames, 'collection', 'stems-dir']
      : [...trackNames, 'output'];
  const missing = required.filter((name) => !args[name]);
  if (missing.length) {
    usage();
    throw new Error(`Missing required options: ${missing.join(', ')}`);
  }

  const ffmpeg = process.env.STEM_PACKAGER_FFMPEG || 'ffmpeg';
  const ffprobe = process.env.STEM_PACKAGER_FFPROBE || 'ffprobe';
  const inputs = Object.fromEntries(trackNames.map((name) => [name, resolve(args[name])]));
  let masterMetadata = {};
  try {
    masterMetadata = await readMasterMetadata(inputs.master);
  } catch (error) {
    console.warn(`Could not read embedded master metadata: ${error.message}`);
  }
  const probedEntries = await Promise.all(
    Object.entries(inputs).map(async ([name, file]) => [name, await probeAudio(file, ffprobe)]),
  );
  const info = Object.fromEntries(probedEntries);
  const common = validateSet(info);
  if (mode === 'native-alac') {
    const incompatible = Object.entries(info).filter(([, track]) =>
      track.sampleRate !== 44100 || (track.bitsPerSample && track.bitsPerSample !== 16));
    if (incompatible.length) {
      throw new Error('Lossless linked mode currently requires five matching stereo 16-bit/44.1 kHz sources.');
    }
  }

  console.log(`Validated five stereo tracks: ${common.sampleRate} Hz, ${common.duration.toFixed(3)} seconds`);
  console.log('Analyzing the unprocessed four-stem sum…');
  const sumAnalysis = await analyzeStemSum(
    [inputs.drums, inputs.bass, inputs.other, inputs.vocals],
    ffmpeg,
  );
  const masteringDsp = createProtectiveDsp(sumAnalysis);
  console.log(
    `Stem sum: ${sumAnalysis.integratedLufs.toFixed(1)} LUFS, ${sumAnalysis.truePeakDbfs.toFixed(1)} dBFS true peak; ` +
    `compressor off, limiter ${masteringDsp.limiter.enabled ? 'on' : 'off'}.`,
  );
  if (validateOnly) {
    console.log(`VALIDATION_RESULT ${JSON.stringify({
      compatible: true,
      sampleRate: common.sampleRate,
      channels: common.channels,
      duration: common.duration,
      stemSumLufs: sumAnalysis.integratedLufs,
      stemSumTruePeakDbfs: sumAnalysis.truePeakDbfs,
      compressorEnabled: masteringDsp.compressor.enabled,
      limiterEnabled: masteringDsp.limiter.enabled,
      limiterCeilingDbfs: masteringDsp.limiter.ceiling,
    })}`);
    return;
  }
  const work = await mkdtemp(join(tmpdir(), 'traktor-stem-packager-'));

  try {
    if (mode === 'native-alac') {
      console.log('Creating lossless ALAC streams in Traktor native-linked format…');
      const stemNames = [
        args['drums-name'] || 'Drums',
        args['bass-name'] || 'Bass',
        args['other-name'] || 'Other',
        args['vocals-name'] || 'Vocals',
      ];
      const result = await createNativeLinkedAlac({
        inputs,
        collectionPath: resolve(args.collection),
        stemsDirectory: resolve(args['stems-dir']),
        temporaryDirectory: work,
        ffmpeg,
        ffprobe,
        masteringDsp,
        stemNames,
      });
      console.log(`Installed linked Stem file: ${result.destination}`);
      console.log(`Collection backup: ${result.collectionBackup}`);
      console.log(`NATIVE_RESULT ${JSON.stringify(result)}`);
      return;
    }

    const encoded = {};
    for (const name of trackNames) {
      const path = join(work, `${name}.m4a`);
      console.log(`Encoding ${name}…`);
      await encodeAac(inputs[name], path, ffmpeg);
      encoded[name] = await readFile(path);
    }

    const output = resolve(args.output);
    let artwork = null;
    let artworkMimeType = 'image/jpeg';
    if (args.artwork) {
      artwork = await readFile(resolve(args.artwork));
      artworkMimeType = /\.png$/i.test(args.artwork) ? 'image/png' : 'image/jpeg';
    } else if (masterMetadata.artworkBase64) {
      artwork = Buffer.from(masterMetadata.artworkBase64, 'base64');
      artworkMimeType = masterMetadata.artworkMimeType || 'image/jpeg';
    }
    console.log('Writing NI Stem metadata and MP4 container…');
    const result = await StemMp4Writer.write({
      outputPath: output,
      mixdownAac: encoded.master,
      stemsAac: {
        drums: encoded.drums,
        bass: encoded.bass,
        other: encoded.other,
        vocals: encoded.vocals,
      },
      metadata: {
        title: args.title || masterMetadata.title || basename(inputs.master, extname(inputs.master)),
        artist: args.artist || masterMetadata.artist || '',
        album: args.album || masterMetadata.album || '',
        genre: args.genre || masterMetadata.genre || '',
        releaseDate: args['release-date'] || args.year || masterMetadata.releaseDate || '',
        producer: args.producer || masterMetadata.producer || '',
        label: args.label || masterMetadata.label || '',
      },
      profile: 'STEMS-4',
      encoderDelaySamples: 1024,
      sampleRate: common.sampleRate,
      masteringDsp,
      stemNames: [
        args['drums-name'] || 'Drums',
        args['bass-name'] || 'Bass',
        args['other-name'] || 'Other',
        args['vocals-name'] || 'Vocals',
      ],
      artwork,
      artworkMimeType,
    });
    console.log(`Created ${result.outputFile} (${(result.fileSizeBytes / 1024 / 1024).toFixed(1)} MiB)`);
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});

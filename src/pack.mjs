#!/usr/bin/env node
import { readFile, rm } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { mkdtemp } from 'node:fs/promises';
import { StemMp4Writer } from 'stem-mp4';
import { analyzeStemSum, createProtectiveDsp, encodeAac, probeAudio, validateSet } from './media.mjs';

function usage() {
  console.error('Usage: node src/pack.mjs --master FILE --drums FILE --bass FILE --other FILE --vocals FILE [--output FILE] [--validate-only true] [--title TITLE] [--artist ARTIST] [--album ALBUM] [--genre GENRE] [--drums-name NAME] [--bass-name NAME] [--other-name NAME] [--vocals-name NAME]');
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
  const validateOnly = args['validate-only'] === 'true';
  const required = validateOnly ? trackNames : [...trackNames, 'output'];
  const missing = required.filter((name) => !args[name]);
  if (missing.length) {
    usage();
    throw new Error(`Missing required options: ${missing.join(', ')}`);
  }

  const ffmpeg = process.env.STEM_PACKAGER_FFMPEG || 'ffmpeg';
  const ffprobe = process.env.STEM_PACKAGER_FFPROBE || 'ffprobe';
  const inputs = Object.fromEntries(trackNames.map((name) => [name, resolve(args[name])]));
  const probedEntries = await Promise.all(
    Object.entries(inputs).map(async ([name, file]) => [name, await probeAudio(file, ffprobe)]),
  );
  const info = Object.fromEntries(probedEntries);
  const common = validateSet(info);

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
        title: args.title || basename(inputs.master).replace(/\.(aif|aiff|wav)$/i, ''),
        artist: args.artist || '',
        album: args.album || '',
        genre: args.genre || '',
        year: args.year || '',
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

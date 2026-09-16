import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export async function probeAudio(file, ffprobe = 'ffprobe') {
  const { stdout } = await execFileAsync(ffprobe, [
    '-v', 'error',
    '-select_streams', 'a:0',
    '-show_entries',
    'stream=codec_name,sample_rate,channels,channel_layout,duration,duration_ts,time_base:format=duration',
    '-of', 'json',
    file,
  ], { maxBuffer: 4 * 1024 * 1024 });

  const parsed = JSON.parse(stdout);
  const stream = parsed.streams?.[0];
  if (!stream) throw new Error(`No audio stream found: ${file}`);

  return {
    file,
    codec: stream.codec_name,
    sampleRate: Number(stream.sample_rate),
    channels: Number(stream.channels),
    channelLayout: stream.channel_layout || '',
    duration: Number(stream.duration ?? parsed.format?.duration),
    durationTicks: stream.duration_ts == null ? null : Number(stream.duration_ts),
    timeBase: stream.time_base || '',
  };
}

export function validateSet(tracks, toleranceSeconds = 0.001) {
  const entries = Object.entries(tracks);
  if (entries.length !== 5) throw new Error('Exactly five tracks are required.');

  const [referenceName, reference] = entries[0];
  const problems = [];

  for (const [name, track] of entries) {
    if (track.sampleRate !== reference.sampleRate) {
      problems.push(`${name}: ${track.sampleRate} Hz does not match ${referenceName}: ${reference.sampleRate} Hz`);
    }
    if (track.channels !== reference.channels) {
      problems.push(`${name}: ${track.channels} channels does not match ${referenceName}: ${reference.channels}`);
    }
    if (Math.abs(track.duration - reference.duration) > toleranceSeconds) {
      problems.push(`${name}: duration ${track.duration.toFixed(6)}s does not match ${referenceName}: ${reference.duration.toFixed(6)}s`);
    }
  }

  if (reference.channels !== 2) problems.push('Traktor Stem inputs must be stereo.');
  const supportedSampleRates = new Set([44100, 48000, 88200, 96000]);
  if (!supportedSampleRates.has(reference.sampleRate)) {
    problems.push(
      `${reference.sampleRate} Hz is not supported in AAC mode. Use matching 44.1, 48, 88.2 or 96 kHz files.`,
    );
  }
  if (problems.length) throw new Error(`Input validation failed:\n${problems.join('\n')}`);
  return { sampleRate: reference.sampleRate, channels: reference.channels, duration: reference.duration };
}

export async function encodeAac(input, output, ffmpeg = 'ffmpeg') {
  await execFileAsync(ffmpeg, [
    '-hide_banner', '-loglevel', 'error', '-y',
    '-i', input,
    '-map_metadata', '-1',
    '-vn',
    '-c:a', 'aac',
    '-b:a', '256k',
    '-movflags', '+faststart',
    output,
  ], { maxBuffer: 16 * 1024 * 1024 });
}

function lastNumber(regex, text, label) {
  const values = [...text.matchAll(regex)];
  if (!values.length) throw new Error(`Could not measure ${label}.`);
  return Number(values.at(-1)[1]);
}

export async function analyzeStemSum(files, ffmpeg = 'ffmpeg') {
  const inputArgs = files.flatMap((file) => ['-i', file]);
  const { stderr } = await execFileAsync(ffmpeg, [
    '-hide_banner', '-nostats',
    ...inputArgs,
    '-filter_complex',
    `[0:a][1:a][2:a][3:a]amix=inputs=4:normalize=0,ebur128=peak=true`,
    '-f', 'null', '-',
  ], { maxBuffer: 16 * 1024 * 1024 });

  return {
    integratedLufs: lastNumber(/I:\s*(-?\d+(?:\.\d+)?) LUFS/g, stderr, 'integrated loudness'),
    truePeakDbfs: lastNumber(/Peak:\s*(-?\d+(?:\.\d+)?) dBFS/g, stderr, 'true peak'),
  };
}

export function createProtectiveDsp(sumAnalysis, ceilingDbfs = -0.3) {
  const limiterNeeded = sumAnalysis.truePeakDbfs > ceilingDbfs;
  return {
    compressor: {
      enabled: false,
      input_gain: 0,
      output_gain: 0,
      threshold: 0,
      dry_wet: 100,
      attack: 0.003,
      release: 0.3,
      ratio: 1,
      hp_cutoff: 20,
    },
    limiter: {
      enabled: limiterNeeded,
      threshold: ceilingDbfs,
      ceiling: ceilingDbfs,
      release: 0.05,
    },
  };
}

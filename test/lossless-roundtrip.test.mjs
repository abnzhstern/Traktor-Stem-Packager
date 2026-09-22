import assert from 'node:assert/strict';
import { execFile, spawnSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { test } from 'node:test';
import { verifyNativePcmRoundTrip } from '../src/native-link.mjs';

const execFileAsync = promisify(execFile);
const ffmpeg = process.env.STEM_PACKAGER_FFMPEG || 'ffmpeg';
const hasFfmpeg = spawnSync(ffmpeg, ['-version'], { stdio: 'ignore' }).status === 0;

test('ALAC package decodes to bit-identical PCM for all five streams', { skip: !hasFfmpeg }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'traktor-lossless-test-'));
  const roles = ['master', 'drums', 'bass', 'other', 'vocals'];
  try {
    const inputs = {};
    for (let index = 0; index < roles.length; index++) {
      const output = join(directory, `${roles[index]}.wav`);
      await execFileAsync(ffmpeg, [
        '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', `sine=frequency=${220 + index * 110}:sample_rate=44100:duration=0.1`,
        '-ac', '2', '-c:a', 'pcm_s16le', output,
      ]);
      inputs[roles[index]] = output;
    }
    const packagedFile = join(directory, 'five-streams.mp4');
    const argumentsList = ['-hide_banner', '-loglevel', 'error', '-y'];
    for (const role of roles) argumentsList.push('-i', inputs[role]);
    for (let index = 0; index < roles.length; index++) argumentsList.push('-map', `${index}:a:0`);
    argumentsList.push('-c:a', 'alac', '-sample_fmt', 's16p', '-ar', '44100', packagedFile);
    await execFileAsync(ffmpeg, argumentsList);

    const verified = await verifyNativePcmRoundTrip({ inputs, packagedFile, ffmpeg });
    assert.equal(verified.length, 5);
    assert.deepEqual(verified.map((item) => item.role), roles);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

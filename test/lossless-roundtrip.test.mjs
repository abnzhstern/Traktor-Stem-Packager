import assert from 'node:assert/strict';
import { execFile, spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { promisify } from 'node:util';
import { test } from 'node:test';
import { createProtectiveDsp } from '../src/media.mjs';
import { createNativeLinkedAlac } from '../src/native-link.mjs';

const execFileAsync = promisify(execFile);
const ffmpeg = process.env.STEM_PACKAGER_FFMPEG || 'ffmpeg';
const ffprobe = process.env.STEM_PACKAGER_FFPROBE || 'ffprobe';
const hasMediaTools = spawnSync(ffmpeg, ['-version'], { stdio: 'ignore' }).status === 0 &&
  spawnSync(ffprobe, ['-version'], { stdio: 'ignore' }).status === 0;
const audioId =
  'ALsd7/94mt9nd3ZDRmaIZTNIdWiGQ0ZmiHVDTnd3dkNWdoh1M1+FaPdUX4ea///////////////////////////' +
  'N3v///////////////////////6zu/5iYh1RWd5l2Q1mneadUVnaal0NNZDM0Q0RDNEQzTXM01kNNdEXf////' +
  '////////////////////////////////////////////////////hTM0MjNDIzQyNEQiNDIzRCM0MjaZMzRDNpl' +
  'ERUNImUN5lDeaqr3v/Hp4ZUSP//////////////////////////////////////////////////3d3YcgAA==';

test('16/44.1 and 24/48 ALAC packages decode to bit-identical PCM', { skip: !hasMediaTools }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'traktor-lossless-test-'));
  const roles = ['master', 'drums', 'bass', 'other', 'vocals'];
  try {
    for (const profile of [
      { bits: 16, rate: 44100, pcm: 'pcm_s16le', format: 's16p' },
      { bits: 24, rate: 48000, pcm: 'pcm_s24le', format: 's32p' },
    ]) {
      const inputs = {};
      for (let index = 0; index < roles.length; index++) {
        const output = join(directory, `${roles[index]}-${profile.bits}.wav`);
        await execFileAsync(ffmpeg, [
          '-hide_banner', '-loglevel', 'error', '-y',
          '-f', 'lavfi', '-i', `sine=frequency=${220 + index * 110}:sample_rate=${profile.rate}:duration=0.1`,
          '-ac', '2', '-c:a', profile.pcm, output,
        ]);
        inputs[roles[index]] = output;
      }
      const profileDirectory = join(directory, `profile-${profile.bits}`);
      const stemsDirectory = join(profileDirectory, 'stems');
      const workDirectory = join(profileDirectory, 'work');
      await mkdir(stemsDirectory, { recursive: true });
      await mkdir(workDirectory, { recursive: true });
      const encodedDirectory = `${dirname(inputs.master).replaceAll('/', '/:')}/:`;
      const collectionPath = join(profileDirectory, 'collection.nml');
      await writeFile(collectionPath,
        `<NML><COLLECTION><ENTRY AUDIO_ID="${audioId}"><LOCATION DIR="${encodedDirectory}" FILE="${inputs.master.split('/').at(-1)}"/><INFO FLAGS="0"/></ENTRY></COLLECTION></NML>`,
      );

      const result = await createNativeLinkedAlac({
        inputs,
        collectionPath,
        stemsDirectory,
        temporaryDirectory: workDirectory,
        ffmpeg,
        ffprobe,
        masteringDsp: createProtectiveDsp({ truePeakDbfs: -1 }),
        stemNames: ['Drums', 'Bass', 'Other', 'Vocals'],
        audioProfile: { sampleRate: profile.rate, bitsPerSample: profile.bits },
      });
      assert.equal(result.verifiedStreams, 5);
      assert.equal(result.sampleRate, profile.rate);
      assert.equal(result.bitsPerSample, profile.bits);
      assert.match(await readFile(collectionPath, 'utf8'), /FLAGS="64"/);
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

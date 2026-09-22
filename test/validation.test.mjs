import test from 'node:test';
import assert from 'node:assert/strict';
import { createProtectiveDsp, validateNativeSourceSet, validateSet } from '../src/media.mjs';

const base = { sampleRate: 48000, channels: 2, duration: 180 };

test('accepts five matching stereo tracks', () => {
  const result = validateSet({ master: base, drums: base, bass: base, other: base, vocals: base });
  assert.equal(result.sampleRate, 48000);
});

test('rejects a sample-rate mismatch', () => {
  const wrong = { ...base, sampleRate: 44100 };
  assert.throws(
    () => validateSet({ master: base, drums: wrong, bass: base, other: base, vocals: base }),
    /does not match/,
  );
});

test('explains file problems in plain language', () => {
  const wrong = { ...base, sampleRate: 44100, channels: 1, duration: 178.5 };
  assert.throws(
    () => validateSet({ master: base, drums: wrong, bass: base, other: base, vocals: base }),
    (error) => {
      assert.match(error.message, /Drums is 44\.1 kHz/);
      assert.match(error.message, /Drums is mono/);
      assert.match(error.message, /same start and end points/);
      return true;
    },
  );
});

test('rejects 192 kHz until a compatible lossless mode is available', () => {
  const highRate = { ...base, sampleRate: 192000 };
  assert.throws(
    () => validateSet({ master: highRate, drums: highRate, bass: highRate, other: highRate, vocals: highRate }),
    /not supported in AAC mode/,
  );
});

test('enables only the limiter when the stem sum exceeds the ceiling', () => {
  const dsp = createProtectiveDsp({ truePeakDbfs: 3.8 }, -0.3);
  assert.equal(dsp.compressor.enabled, false);
  assert.equal(dsp.limiter.enabled, true);
  assert.equal(dsp.limiter.ceiling, -0.3);
});

test('disables dynamics when the stem sum has safe headroom', () => {
  const dsp = createProtectiveDsp({ truePeakDbfs: -1.2 }, -0.3);
  assert.equal(dsp.compressor.enabled, false);
  assert.equal(dsp.limiter.enabled, false);
});

test('lossless mode accepts only explicit 16-bit 44.1 kHz PCM', () => {
  const pcm = { codec: 'pcm_s16le', bitsPerSample: 16, sampleRate: 44100 };
  assert.doesNotThrow(() => validateNativeSourceSet({
    master: pcm, drums: pcm, bass: pcm, other: pcm, vocals: pcm,
  }));
  assert.throws(() => validateNativeSourceSet({
    master: { ...pcm, codec: 'aac', bitsPerSample: 0 },
    drums: pcm, bass: pcm, other: pcm, vocals: pcm,
  }), /Compressed or ambiguous sources are rejected/);

  const pcm24 = { codec: 'pcm_s24le', bitsPerSample: 24, sampleRate: 48000 };
  assert.deepEqual(validateNativeSourceSet({
    master: pcm24, drums: pcm24, bass: pcm24, other: pcm24, vocals: pcm24,
  }), { sampleRate: 48000, bitsPerSample: 24 });
});

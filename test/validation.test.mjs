import test from 'node:test';
import assert from 'node:assert/strict';
import { createProtectiveDsp, validateSet } from '../src/media.mjs';

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

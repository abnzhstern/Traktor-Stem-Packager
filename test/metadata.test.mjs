import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizeMasterMetadata } from '../src/metadata.mjs';

test('normalizes master tags and embedded artwork', () => {
  const metadata = normalizeMasterMetadata({
    title: 'Night Drive',
    artist: 'Example Artist',
    album: 'After Hours',
    releasedate: '2026-09-16',
    producer: ['Producer One', 'Producer Two'],
    label: ['Neon Records'],
    genre: ['Electronic', 'House'],
    picture: [{ format: 'image/png', data: Uint8Array.from([1, 2, 3]) }],
  }, '/music/wrong filename.wav');

  assert.deepEqual(metadata, {
    title: 'Night Drive',
    artist: 'Example Artist',
    album: 'After Hours',
    releaseDate: '2026-09-16',
    producer: 'Producer One; Producer Two',
    label: 'Neon Records',
    genre: 'Electronic; House',
    artworkBase64: 'AQID',
    artworkMimeType: 'image/png',
  });
});

test('uses compatible fallbacks without treating the whole path as a title', () => {
  const metadata = normalizeMasterMetadata({
    artists: ['Artist A', 'Artist B'],
    year: 2025,
    publisher: ['Independent Label'],
  }, '/music/My Track.aiff');

  assert.equal(metadata.title, 'My Track');
  assert.equal(metadata.artist, 'Artist A; Artist B');
  assert.equal(metadata.releaseDate, '2025');
  assert.equal(metadata.label, 'Independent Label');
});

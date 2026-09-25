import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  findCollectionEntry,
  inspectCollectionEntry,
  markEntryHasLinkedStems,
  nativeStemRelativePath,
} from '../src/native-link.mjs';

const goodVibrationsAudioId =
  'ALsd7/94mt9nd3ZDRmaIZTNIdWiGQ0ZmiHVDTnd3dkNWdoh1M1+FaPdUX4ea///////////////////////////' +
  'N3v///////////////////////6zu/5iYh1RWd5l2Q1mneadUVnaal0NNZDM0Q0RDNEQzTXM01kNNdEXf////' +
  '////////////////////////////////////////////////////hTM0MjNDIzQyNEQiNDIzRCM0MjaZMzRDNpl' +
  'ERUNImUN5lDeaqr3v/Hp4ZUSP//////////////////////////////////////////////////3d3YcgAA==';

test('derives Traktor native path from AUDIO_ID', () => {
  assert.equal(
    nativeStemRelativePath(goodVibrationsAudioId),
    '056/YNB5YZACIWLCQDMCDFGUDOYEB45D.stem.mp4',
  );
});

test('reports collection readiness without mutating the collection', () => {
  const unanalyzed = '<NML><COLLECTION><ENTRY><LOCATION DIR="/:Users/:andrew/:Music/:" FILE="x.aif"/></ENTRY></COLLECTION></NML>';
  const missingId = inspectCollectionEntry(unanalyzed, '/Users/andrew/Music/x.aif');
  assert.equal(missingId.found, true);
  assert.equal(missingId.ready, false);
  assert.equal(missingId.hasAudioId, false);
  assert.equal(missingId.collectionLinked, false);

  const absent = inspectCollectionEntry(unanalyzed, '/Users/andrew/Music/y.aif');
  assert.equal(absent.found, false);
  assert.equal(absent.ready, false);
  assert.equal(absent.collectionLinked, false);
});

test('finds the exact master and sets linked-stem flag without disturbing other flags', () => {
  const collection = `<?xml version="1.0"?><NML><COLLECTION ENTRIES="1">
<ENTRY TITLE="Take My Mind" AUDIO_ID="${goodVibrationsAudioId}">
<LOCATION DIR="/:Users/:andrew/:Music/:" FILE="Take My Mind.aif" VOLUME="Macintosh HD"/>
<INFO FLAGS="12" GENRE="Pop"/>
</ENTRY></COLLECTION></NML>`;
  const found = findCollectionEntry(collection, '/Users/andrew/Music/Take My Mind.aif');
  assert.equal(found.audioId, goodVibrationsAudioId);
  assert.equal(inspectCollectionEntry(collection, '/Users/andrew/Music/Take My Mind.aif').collectionLinked, false);
  const updated = markEntryHasLinkedStems(collection, found);
  assert.match(updated, /<INFO FLAGS="76" GENRE="Pop"\/>/);
  assert.equal(inspectCollectionEntry(updated, '/Users/andrew/Music/Take My Mind.aif').collectionLinked, true);
  assert.match(updated, /TITLE="Take My Mind"/);
});

test('adds INFO when the collection entry has none', () => {
  const collection = `<NML><COLLECTION><ENTRY AUDIO_ID="${goodVibrationsAudioId}"><LOCATION DIR="/:Users/:andrew/:Music/:" FILE="x.aif"/></ENTRY></COLLECTION></NML>`;
  const found = findCollectionEntry(collection, '/Users/andrew/Music/x.aif');
  assert.match(markEntryHasLinkedStems(collection, found), /<INFO FLAGS="64"\/>/);
});

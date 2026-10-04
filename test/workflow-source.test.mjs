import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

const modelPath = new URL('../macos/Sources/TraktorStemPackager/PackagerModel.swift', import.meta.url);
const viewPath = new URL('../macos/Sources/TraktorStemPackager/ContentView.swift', import.meta.url);

test('keeps Traktor status actions visible without a global workflow phase', async () => {
  const [model, view] = await Promise.all([
    readFile(modelPath, 'utf8'),
    readFile(viewPath, 'utf8'),
  ]);

  assert.doesNotMatch(model, /enum WorkflowPhase/);
  assert.doesNotMatch(model, /packageFingerprint/);
  assert.match(model, /func refreshTraktorStateFromUser\(\) async/);
  assert.match(model, /func saveQuitTraktorAndRefresh\(\) async/);
  assert.match(view, /Button\("SAVE & QUIT TRAKTOR, THEN REFRESH"\)/);
  assert.match(view, /else if model\.canAddRemainingStems/);
});

test('preserves the installed state and uses attached main-window file panels', async () => {
  const [model, view] = await Promise.all([
    readFile(modelPath, 'utf8'),
    readFile(viewPath, 'utf8'),
  ]);

  assert.match(model, /if case \.complete = state,[\s\S]*result\.collectionLinked,[\s\S]*result\.linkedStemExists/);
  assert.match(view, /panel\.beginSheetModal\(for: window\)/);
  assert.doesNotMatch(view, /panel\.runModal\(\)/);
});

test('collects all audio before the lossless Traktor handoff', async () => {
  const [model, view] = await Promise.all([
    readFile(modelPath, 'utf8'),
    readFile(viewPath, 'utf8'),
  ]);

  const addRemainingRule = model.match(/var canAddRemainingStems: Bool \{([\s\S]*?)\n    \}/)?.[1] ?? '';
  assert.match(addRemainingRule, /files\[\.master\] != nil/);
  assert.doesNotMatch(addRemainingRule, /nativeReadiness/);
  assert.doesNotMatch(addRemainingRule, /traktorRefreshRequiresSave/);
  assert.match(model, /func importRemainingStemsFolder\(_ directory: URL\)/);
  assert.match(view, /Button\("ADD REMAINING STEMS"\)/);
  assert.match(view, /Text\("OR"\)/);
  assert.match(view, /Button\("IMPORT STEMS FOLDER"\)/);
  assert.match(view, /model\.hasAllFiles,[\s\S]*model\.state != \.packaging/);
});

test('gives explicit master import, analysis, and playback instructions', async () => {
  const view = await readFile(viewPath, 'utf8');

  assert.match(view, /IMPORT & ANALYZE MASTER/);
  assert.match(view, /drag the highlighted file into Traktor’s Track Collection—not onto a deck—and analyze it/);
  assert.match(view, /I FINISHED — CLOSE & VERIFY/);
  assert.match(view, /Load as Track/);
  assert.match(view, /Load as Stem/);
  assert.doesNotMatch(view, /Let Traktor finish analyzing the stereo master/);
});

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

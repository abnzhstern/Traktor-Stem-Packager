#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { inspectCollectionEntry } from './native-link.mjs';

function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    if (!key?.startsWith('--') || argv[index + 1] == null) throw new Error(`Invalid argument: ${key ?? ''}`);
    options[key.slice(2)] = argv[index + 1];
  }
  return options;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.master || !args.collection) throw new Error('Master and collection paths are required.');
  const collection = await readFile(resolve(args.collection), 'utf8');
  const result = inspectCollectionEntry(collection, resolve(args.master));
  console.log(`NATIVE_READINESS_RESULT ${JSON.stringify({
    ready: result.ready,
    found: result.found,
    hasAudioId: result.hasAudioId,
    message: result.message,
  })}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});

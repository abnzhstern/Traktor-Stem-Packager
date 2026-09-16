#!/usr/bin/env node
import { resolve } from 'node:path';
import { readMasterMetadata } from './metadata.mjs';

const marker = '--master';
const index = process.argv.indexOf(marker);
if (index < 0 || !process.argv[index + 1]) {
  console.error('Usage: node src/read-metadata.mjs --master FILE');
  process.exitCode = 1;
} else {
  try {
    const metadata = await readMasterMetadata(resolve(process.argv[index + 1]));
    console.log(`MASTER_METADATA ${JSON.stringify(metadata)}`);
  } catch (error) {
    console.error(`Could not read master metadata: ${error.message}`);
    process.exitCode = 1;
  }
}

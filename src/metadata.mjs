import { basename, extname } from 'node:path';
import { parseFile } from 'music-metadata';

function text(value) {
  if (value == null) return '';
  return String(value).trim();
}

function joined(value) {
  const values = Array.isArray(value) ? value : value == null ? [] : [value];
  return values.map(text).filter(Boolean).join('; ');
}

export function normalizeMasterMetadata(common = {}, file = '') {
  const picture = Array.isArray(common.picture) ? common.picture[0] : null;
  const fallbackTitle = file ? basename(file, extname(file)) : '';
  return {
    title: text(common.title) || fallbackTitle,
    artist: text(common.artist) || joined(common.artists),
    album: text(common.album),
    releaseDate:
      text(common.releasedate) ||
      text(common.date) ||
      text(common.originaldate) ||
      text(common.year),
    producer: joined(common.producer),
    label: joined(common.label) || joined(common.publisher),
    genre: joined(common.genre),
    artworkBase64: picture?.data ? Buffer.from(picture.data).toString('base64') : null,
    artworkMimeType: text(picture?.format) || null,
  };
}

export async function readMasterMetadata(file) {
  const parsed = await parseFile(file, { duration: false });
  return normalizeMasterMetadata(parsed.common, file);
}

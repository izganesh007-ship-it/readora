import { signedObjectUrl } from './storage.js';

export async function signedEbookUrl(key: string, filename: string) {
  return signedObjectUrl(key, filename, 'attachment');
}

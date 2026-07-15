import { signedObjectUrl } from './storage.js';
export async function signedEbookUrl(key, filename) {
    return signedObjectUrl(key, filename, 'attachment');
}

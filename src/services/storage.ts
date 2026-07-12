import fs from 'node:fs/promises';
import path from 'node:path';
import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../config/env.js';
import { signLocalFileToken } from './localFileToken.js';

const s3 = new S3Client({
  region: env.R2_REGION,
  endpoint: env.R2_ENDPOINT,
  credentials: env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY ? {
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY
  } : undefined
});

export function safeStorageKey(kind: string, filename: string) {
  const safe = filename.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '');
  return `${kind}/${Date.now()}-${safe || 'file'}`;
}

export function localPathForKey(key: string) {
  const root = path.resolve(env.LOCAL_STORAGE_DIR);
  const full = path.resolve(root, key);
  if (!full.startsWith(root + path.sep)) throw new Error('Invalid storage key');
  return full;
}

export async function saveLocalObject(key: string, data: Buffer | string) {
  const filePath = localPathForKey(key);
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, data);
  return key;
}

export async function readTextObject(key: string) {
  if (env.STORAGE_DRIVER === 'local') {
    return fs.readFile(localPathForKey(key), 'utf8');
  }
  if (!env.R2_BUCKET) throw new Error('R2_BUCKET is not configured');
  const out = await s3.send(new GetObjectCommand({ Bucket: env.R2_BUCKET, Key: key }));
  return out.Body?.transformToString('utf8') ?? '';
}

export async function signedObjectUrl(key: string, filename: string, disposition: 'inline' | 'attachment' = 'attachment') {
  if (env.STORAGE_DRIVER === 'local') {
    const token = signLocalFileToken({ key, filename, disposition }, env.SIGNED_URL_SECONDS);
    return `${env.APP_URL.replace(/\/$/, '')}/api/files/${token}`;
  }
  if (!env.R2_BUCKET) throw new Error('R2_BUCKET is not configured');
  const cmd = new GetObjectCommand({
    Bucket: env.R2_BUCKET,
    Key: key,
    ResponseContentDisposition: `${disposition}; filename="${filename.replace(/"/g, '')}"`
  });
  return getSignedUrl(s3, cmd, { expiresIn: env.SIGNED_URL_SECONDS });
}

export async function signedUploadTarget(input: { kind: 'cover' | 'epub' | 'pdf' | 'reader-html' | 'reader-txt' | 'reader-pdf'; filename: string; contentType: string }) {
  const key = safeStorageKey(input.kind, input.filename);
  if (env.STORAGE_DRIVER === 'local') {
    return { driver: 'local' as const, key, uploadUrl: null, method: 'POST', note: 'Use POST /api/admin/uploads/local with this key and base64 content.' };
  }
  if (!env.R2_BUCKET) throw new Error('R2_BUCKET is not configured');
  const cmd = new PutObjectCommand({ Bucket: env.R2_BUCKET, Key: key, ContentType: input.contentType });
  const uploadUrl = await getSignedUrl(s3, cmd, { expiresIn: 300 });
  return { driver: env.STORAGE_DRIVER, key, uploadUrl, method: 'PUT', expiresInSeconds: 300 };
}

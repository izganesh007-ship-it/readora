import fs from 'node:fs/promises';
import path from 'node:path';
import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../config/env.js';
import { signLocalFileToken } from './localFileToken.js';
function getS3Client() {
    const isB2 = env.STORAGE_DRIVER === 'b2';
    const endpoint = isB2 ? env.B2_ENDPOINT : env.R2_ENDPOINT;
    const accessKeyId = isB2 ? env.B2_KEY_ID : env.R2_ACCESS_KEY_ID;
    const secretAccessKey = isB2 ? env.B2_APPLICATION_KEY : env.R2_SECRET_ACCESS_KEY;
    const region = isB2 ? (env.B2_REGION || 'us-east-005') : env.R2_REGION;
    return new S3Client({
        region,
        endpoint,
        forcePathStyle: isB2,
        credentials: accessKeyId && secretAccessKey ? {
            accessKeyId,
            secretAccessKey
        } : undefined
    });
}
const s3 = getS3Client();
function getBucket() {
    const bucket = env.STORAGE_DRIVER === 'b2' ? env.B2_BUCKET : env.R2_BUCKET;
    if (!bucket)
        throw new Error(`${env.STORAGE_DRIVER === 'b2' ? 'B2_BUCKET' : 'R2_BUCKET'} is not configured`);
    return bucket;
}
export function safeStorageKey(kind, filename) {
    const safe = filename.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '');
    return `${kind}/${Date.now()}-${safe || 'file'}`;
}
export function localPathForKey(key) {
    const root = path.resolve(env.LOCAL_STORAGE_DIR);
    const full = path.resolve(root, key);
    if (!full.startsWith(root + path.sep))
        throw new Error('Invalid storage key');
    return full;
}
export async function saveLocalObject(key, data) {
    const filePath = localPathForKey(key);
    await fs.mkdir(path.dirname(filePath), { recursive: true });
    await fs.writeFile(filePath, data);
    return key;
}
export async function readTextObject(key) {
    if (env.STORAGE_DRIVER === 'local') {
        return fs.readFile(localPathForKey(key), 'utf8');
    }
    const out = await s3.send(new GetObjectCommand({ Bucket: getBucket(), Key: key }));
    return out.Body?.transformToString('utf8') ?? '';
}
export async function signedObjectUrl(key, filename, disposition = 'attachment') {
    if (env.STORAGE_DRIVER === 'local') {
        const token = signLocalFileToken({ key, filename, disposition }, env.SIGNED_URL_SECONDS);
        return `${env.APP_URL.replace(/\/$/, '')}/api/files/${token}`;
    }
    const cmd = new GetObjectCommand({
        Bucket: getBucket(),
        Key: key,
        ResponseContentDisposition: `${disposition}; filename="${filename.replace(/"/g, '')}"`
    });
    return getSignedUrl(s3, cmd, { expiresIn: env.SIGNED_URL_SECONDS });
}
export async function signedUploadTarget(input) {
    const key = safeStorageKey(input.kind, input.filename);
    if (env.STORAGE_DRIVER === 'local') {
        return { driver: 'local', key, uploadUrl: null, method: 'POST', note: 'Use POST /api/admin/uploads/local with this key and base64 content.' };
    }
    const cmd = new PutObjectCommand({ Bucket: getBucket(), Key: key, ContentType: input.contentType });
    const uploadUrl = await getSignedUrl(s3, cmd, { expiresIn: 300 });
    return { driver: env.STORAGE_DRIVER, key, uploadUrl, method: 'PUT', expiresInSeconds: 300 };
}

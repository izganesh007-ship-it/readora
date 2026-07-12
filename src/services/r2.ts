import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../config/env.js';

const s3 = new S3Client({
  region: env.R2_REGION,
  endpoint: env.R2_ENDPOINT,
  credentials: env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY ? {
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY
  } : undefined
});

export async function signedEbookUrl(key: string, filename: string) {
  if (!env.R2_BUCKET) throw new Error('R2_BUCKET is not configured');
  const cmd = new GetObjectCommand({
    Bucket: env.R2_BUCKET,
    Key: key,
    ResponseContentDisposition: `attachment; filename="${filename.replace(/"/g, '')}"`
  });
  return getSignedUrl(s3, cmd, { expiresIn: env.SIGNED_URL_SECONDS });
}

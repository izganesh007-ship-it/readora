import crypto from 'node:crypto';
import { env } from '../config/env.js';

export type LocalFileTokenPayload = {
  key: string;
  filename: string;
  disposition: 'inline' | 'attachment';
  exp: number;
};

function b64url(input: string | Buffer) {
  return Buffer.from(input).toString('base64url');
}

export function signLocalFileToken(payload: Omit<LocalFileTokenPayload, 'exp'>, seconds = env.SIGNED_URL_SECONDS) {
  const full: LocalFileTokenPayload = { ...payload, exp: Math.floor(Date.now() / 1000) + seconds };
  const encoded = b64url(JSON.stringify(full));
  const sig = crypto.createHmac('sha256', env.JWT_SECRET).update(encoded).digest('base64url');
  return `${encoded}.${sig}`;
}

export function verifyLocalFileToken(token: string): LocalFileTokenPayload | null {
  const [encoded, sig] = token.split('.');
  if (!encoded || !sig) return null;
  const expected = crypto.createHmac('sha256', env.JWT_SECRET).update(encoded).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8')) as LocalFileTokenPayload;
  if (payload.exp < Math.floor(Date.now() / 1000)) return null;
  return payload;
}

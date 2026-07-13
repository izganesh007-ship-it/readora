import crypto from 'node:crypto';
import { env } from '../config/env.js';
function b64url(input) {
    return Buffer.from(input).toString('base64url');
}
export function signLocalFileToken(payload, seconds = env.SIGNED_URL_SECONDS) {
    const full = { ...payload, exp: Math.floor(Date.now() / 1000) + seconds };
    const encoded = b64url(JSON.stringify(full));
    const sig = crypto.createHmac('sha256', env.JWT_SECRET).update(encoded).digest('base64url');
    return `${encoded}.${sig}`;
}
export function verifyLocalFileToken(token) {
    const [encoded, sig] = token.split('.');
    if (!encoded || !sig)
        return null;
    const expected = crypto.createHmac('sha256', env.JWT_SECRET).update(encoded).digest('base64url');
    const a = Buffer.from(sig);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b))
        return null;
    const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
    if (payload.exp < Math.floor(Date.now() / 1000))
        return null;
    return payload;
}

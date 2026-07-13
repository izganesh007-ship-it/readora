import crypto from 'node:crypto';
export function newPurchaseAccessToken() {
    return 'pa_' + crypto.randomBytes(32).toString('base64url');
}
export function hashPurchaseAccessToken(token) {
    return crypto.createHash('sha256').update(token, 'utf8').digest('hex');
}

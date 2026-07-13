import crypto from 'node:crypto';
import { env } from '../config/env.js';
export function hashToken(token) {
    return crypto.createHash('sha256').update(token, 'utf8').digest('hex');
}
export function newDownloadToken() {
    return 'rd_' + crypto.randomBytes(32).toString('base64url');
}
export async function createDownloadLink(client, purchaseId, bookId) {
    const token = newDownloadToken();
    const tokenHash = hashToken(token);
    const expires = new Date(Date.now() + env.DOWNLOAD_TOKEN_HOURS * 60 * 60 * 1000);
    await client.query(`INSERT INTO download_links(purchase_id, book_id, token_hash, expires_at)
     VALUES ($1,$2,$3,$4)`, [purchaseId, bookId, tokenHash, expires]);
    return { token, expiresAt: expires };
}

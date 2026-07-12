import { Router } from 'express';
import { tx } from '../db.js';
import { hashToken } from '../services/downloadToken.js';
import { signedObjectUrl } from '../services/storage.js';
import { audit } from '../services/audit.js';

export const downloadsRouter = Router();

downloadsRouter.post('/:token/redeem', async (req, res, next) => {
  try {
    const tokenHash = hashToken(req.params.token);
    const result = await tx(async client => {
      const link = await client.query(
        `SELECT dl.*, b.title, b.epub_key, b.pdf_key FROM download_links dl
         JOIN books b ON b.id=dl.book_id
         WHERE dl.token_hash=$1 FOR UPDATE`,
        [tokenHash]
      );
      if (!link.rowCount) return { status: 404 as const, error: 'Download link not found' };
      const row = link.rows[0];
      if (row.status !== 'ACTIVE' || new Date(row.expires_at) < new Date()) {
        await client.query(`UPDATE download_links SET status='EXPIRED' WHERE id=$1 AND status='ACTIVE'`, [row.id]);
        return { status: 410 as const, error: 'Download link expired' };
      }
      const key = row.epub_key || row.pdf_key;
      if (!key) return { status: 404 as const, error: 'No ebook file is configured' };
      await client.query(`UPDATE download_links SET status='USED', redeemed_at=now(), redeemed_ip=$2, user_agent=$3 WHERE id=$1`, [row.id, req.ip, req.get('user-agent') || '']);
      return { status: 200 as const, url: await signedObjectUrl(key, `${row.title}.epub`, 'attachment') };
    });
    if ('error' in result) return res.status(result.status).json({ error: result.error });
    await audit('DOWNLOAD_TOKEN_REDEEMED', { ip: req.ip, metadata: { tokenHash } });
    res.json({ signedUrl: result.url, expiresInSeconds: 300 });
  } catch (err) { next(err); }
});

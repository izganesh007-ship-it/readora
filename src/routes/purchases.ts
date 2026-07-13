import { Router } from 'express';
import { z } from 'zod';
import { query, tx } from '../db.js';
import { createDownloadLink } from '../services/downloadToken.js';
import { hashPurchaseAccessToken } from '../services/purchaseAccess.js';
import { audit } from '../services/audit.js';

export const purchasesRouter = Router();

purchasesRouter.get('/:id', async (req, res, next) => {
  try {
    const q = z.object({
      accessToken: z.string().min(10)
    }).parse(req.query);

    const tokenHash = hashPurchaseAccessToken(q.accessToken);

    const out = await query(
      `SELECT p.id,p.status,p.amount_cents,p.currency,p.created_at,p.paid_at,p.btcpay_checkout_link,b.title,b.slug,b.author
       FROM purchases p
       JOIN books b ON b.id=p.book_id
       WHERE p.id=$1 AND p.access_token_hash=$2`,
      [req.params.id, tokenHash]
    );

    if (!out.rowCount) return res.status(404).json({ error: 'Purchase not found' });

    res.json({ data: out.rows[0] });
  } catch (err) {
    next(err);
  }
});

purchasesRouter.post('/:id/download-token', async (req, res, next) => {
  try {
    const body = z.object({
      accessToken: z.string().min(10)
    }).parse(req.body);

    const tokenHash = hashPurchaseAccessToken(body.accessToken);

    const result = await tx(async client => {
      const p = await client.query(
        `SELECT p.*, b.title
         FROM purchases p
         JOIN books b ON b.id=p.book_id
         WHERE p.id=$1 AND p.access_token_hash=$2
         FOR UPDATE`,
        [req.params.id, tokenHash]
      );

      if (!p.rowCount) return { status: 404 as const, error: 'Purchase not found' };
      if (p.rows[0].status !== 'PAID') return { status: 402 as const, error: 'Payment not confirmed yet' };

      const used = await client.query(
        `SELECT id FROM download_links
         WHERE purchase_id=$1 AND status='USED'
         LIMIT 1`,
        [p.rows[0].id]
      );

      if (used.rowCount) {
        return { status: 410 as const, error: 'Download already used' };
      }

      const active = await client.query(
        `SELECT token_hash, expires_at FROM download_links
         WHERE purchase_id=$1 AND status='ACTIVE' AND expires_at > now()
         LIMIT 1`,
        [p.rows[0].id]
      );

      if (active.rowCount) {
        await client.query(
          `UPDATE download_links
           SET status='REVOKED'
           WHERE purchase_id=$1 AND status='ACTIVE'`,
          [p.rows[0].id]
        );
      }

      const link = await createDownloadLink(client, p.rows[0].id, p.rows[0].book_id);

      return {
        status: 201 as const,
        token: link.token,
        expiresAt: link.expiresAt
      };
    });

    if ('error' in result) return res.status(result.status).json({ error: result.error });

    await audit('DOWNLOAD_TOKEN_ISSUED', {
      entityType: 'purchase',
      entityId: req.params.id,
      ip: req.ip
    });

    res.status(201).json({
      token: result.token,
      expiresAt: result.expiresAt
    });
  } catch (err) {
    next(err);
  }
});

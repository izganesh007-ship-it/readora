import { Router } from 'express';
import { tx } from '../db.js';
import { verifyWebhook } from '../services/btcpay.js';
import { audit } from '../services/audit.js';
export const webhooksRouter = Router();
webhooksRouter.post('/btcpay', async (req, res, next) => {
    try {
        const sig = req.get('BTCPay-Sig') || req.get('btcpay-sig');
        const raw = req.rawBody || Buffer.from(JSON.stringify(req.body || {}));
        if (!verifyWebhook(raw, sig))
            return res.status(401).json({ error: 'Invalid webhook signature' });
        const event = req.body;
        const invoiceId = event.invoiceId || event.invoice?.id;
        const type = event.type || event.event;
        if (!invoiceId)
            return res.status(202).json({ ok: true });
        if (['InvoiceSettled', 'InvoicePaymentSettled', 'InvoiceProcessing'].includes(type)) {
            await tx(async (client) => {
                const p = await client.query('SELECT * FROM purchases WHERE btcpay_invoice_id=$1 FOR UPDATE', [invoiceId]);
                if (!p.rowCount || p.rows[0].status === 'PAID')
                    return;
                await client.query('UPDATE purchases SET status=\'PAID\', paid_at=now() WHERE id=$1', [p.rows[0].id]);
            });
            await audit('BTCPAY_PURCHASE_CONFIRMED', { entityType: 'invoice', entityId: invoiceId, metadata: event });
        }
        res.json({ ok: true });
    }
    catch (err) {
        next(err);
    }
});

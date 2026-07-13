import { Router } from 'express';
import { tx } from '../db.js';
import { verifyWebhook } from '../services/btcpay.js';
import { verifyNowPaymentsSignature } from '../services/nowpayments.js';
import { createDownloadLink } from '../services/downloadToken.js';
import { audit } from '../services/audit.js';
export const webhooksRouter = Router();
async function markPurchasePaid(input) {
    await tx(async (client) => {
        const p = input.purchaseId
            ? await client.query('SELECT * FROM purchases WHERE id=$1 FOR UPDATE', [input.purchaseId])
            : await client.query('SELECT * FROM purchases WHERE btcpay_invoice_id=$1 FOR UPDATE', [input.providerPaymentId]);
        if (!p.rowCount)
            return;
        const purchase = p.rows[0];
        if (purchase.status !== 'PAID') {
            await client.query(`UPDATE purchases
         SET status='PAID', paid_at=now()
         WHERE id=$1`, [purchase.id]);
        }
        const existing = await client.query(`SELECT id FROM download_links
       WHERE purchase_id=$1 AND status IN ('ACTIVE','USED') LIMIT 1`, [purchase.id]);
        if (!existing.rowCount) {
            await createDownloadLink(client, purchase.id, purchase.book_id);
        }
    });
    await audit(`${input.provider.toUpperCase()}_PURCHASE_CONFIRMED`, {
        entityType: 'payment',
        entityId: input.providerPaymentId || input.purchaseId,
        ip: input.ip,
        metadata: input.payload
    });
}
webhooksRouter.post('/btcpay', async (req, res, next) => {
    try {
        const sig = req.get('BTCPay-Sig') || req.get('btcpay-sig');
        const raw = req.rawBody || Buffer.from(JSON.stringify(req.body || {}));
        if (!verifyWebhook(raw, sig)) {
            return res.status(401).json({ error: 'Invalid webhook signature' });
        }
        const event = req.body;
        const invoiceId = event.invoiceId || event.invoice?.id;
        const type = event.type || event.event;
        if (!invoiceId)
            return res.status(202).json({ ok: true });
        if (['InvoiceSettled', 'InvoicePaymentSettled', 'InvoiceProcessing'].includes(type)) {
            await markPurchasePaid({
                providerPaymentId: invoiceId,
                provider: 'btcpay',
                payload: event,
                ip: req.ip
            });
        }
        res.json({ ok: true });
    }
    catch (err) {
        next(err);
    }
});
webhooksRouter.post('/nowpayments', async (req, res, next) => {
    try {
        const signature = req.get('x-nowpayments-sig') ||
            req.get('X-NOWPAYMENTS-SIG') ||
            req.get('x-nowpayments-signature');
        if (!verifyNowPaymentsSignature(req.body, signature || undefined)) {
            return res.status(401).json({ error: 'Invalid NOWPayments IPN signature' });
        }
        const payload = req.body || {};
        const status = String(payload.payment_status || '').toLowerCase();
        const orderId = payload.order_id ? String(payload.order_id) : undefined;
        const paymentId = payload.payment_id ? String(payload.payment_id) : undefined;
        const paidStatuses = new Set([
            'confirmed',
            'finished',
            'sending',
            'partially_paid'
        ]);
        if (paidStatuses.has(status)) {
            await markPurchasePaid({
                purchaseId: orderId,
                providerPaymentId: paymentId,
                provider: 'nowpayments',
                payload,
                ip: req.ip
            });
        }
        res.json({ ok: true });
    }
    catch (err) {
        next(err);
    }
});

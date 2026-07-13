import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { env } from '../config/env.js';
import { createInvoice } from '../services/btcpay.js';
import { createPayment as createNowPayment } from '../services/nowpayments.js';
import { newPurchaseAccessToken, hashPurchaseAccessToken } from '../services/purchaseAccess.js';
export const checkoutRouter = Router();
checkoutRouter.post('/btcpay', async (req, res, next) => {
    try {
        const body = z.object({
            bookId: z.string().uuid(),
            buyerEmail: z.string().email().optional()
        }).parse(req.body);
        const book = await query('SELECT id,title,slug,access,price_cents,currency FROM books WHERE id=$1 AND is_active=true', [body.bookId]);
        if (!book.rowCount)
            return res.status(404).json({ error: 'Book not found' });
        if (book.rows[0].access === 'FREE')
            return res.status(400).json({ error: 'Free books do not require checkout' });
        const purchaseAccessToken = newPurchaseAccessToken();
        const purchase = await query(`INSERT INTO purchases(book_id,buyer_email,amount_cents,currency,status,access_token_hash)
       VALUES($1,$2,$3,$4,'PENDING',$5)
       RETURNING *`, [
            body.bookId,
            body.buyerEmail || null,
            book.rows[0].price_cents,
            book.rows[0].currency,
            hashPurchaseAccessToken(purchaseAccessToken)
        ]);
        const purchaseId = purchase.rows[0].id;
        const amount = book.rows[0].price_cents / 100;
        if (env.USE_NOWPAYMENTS) {
            const payment = await createNowPayment(purchaseId, book.rows[0].price_cents, (book.rows[0].currency || 'USD').toLowerCase(), `Readora ebook: ${book.rows[0].title}`);
            await query('UPDATE purchases SET btcpay_invoice_id=$1, btcpay_checkout_link=$2 WHERE id=$3', [payment.paymentId, payment.paymentUrl, purchaseId]);
            return res.status(201).json({
                provider: 'nowpayments',
                purchaseId,
                purchaseAccessToken,
                paymentId: payment.paymentId,
                checkoutLink: payment.paymentUrl,
                paymentUrl: payment.paymentUrl,
                payAddress: payment.payAddress
            });
        }
        const invoice = await createInvoice({
            amount,
            currency: book.rows[0].currency || env.BTCPAY_CURRENCY,
            orderId: purchaseId,
            buyerEmail: body.buyerEmail,
            redirectUrl: `${env.APP_URL}/purchase-success?purchase=${purchaseId}`
        });
        await query('UPDATE purchases SET btcpay_invoice_id=$1, btcpay_checkout_link=$2 WHERE id=$3', [invoice.id, invoice.checkoutLink, purchaseId]);
        res.status(201).json({
            provider: env.USE_MOCK_BTCPAY ? 'mock' : 'btcpay',
            purchaseId,
            purchaseAccessToken,
            invoiceId: invoice.id,
            checkoutLink: invoice.checkoutLink
        });
    }
    catch (err) {
        next(err);
    }
});

import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { env } from '../config/env.js';
import { createInvoice } from '../services/btcpay.js';
import { createPayment as createNowPayment } from '../services/nowpayments.js';
import { newPurchaseAccessToken, hashPurchaseAccessToken } from '../services/purchaseAccess.js';

export const checkoutRouter = Router();

async function createPurchase(bookId: string, buyerEmail?: string) {
  const book = await query(
    'SELECT id,title,slug,access,price_cents,currency FROM books WHERE id=$1 AND is_active=true',
    [bookId]
  );

  if (!book.rowCount) return { errorStatus: 404 as const, error: 'Book not found' };
  if (book.rows[0].access === 'FREE') return { errorStatus: 400 as const, error: 'Free books do not require checkout' };

  const purchaseAccessToken = newPurchaseAccessToken();

  const purchase = await query(
    `INSERT INTO purchases(book_id,buyer_email,amount_cents,currency,status,access_token_hash)
     VALUES($1,$2,$3,$4,'PENDING',$5)
     RETURNING *`,
    [
      bookId,
      buyerEmail || null,
      book.rows[0].price_cents,
      book.rows[0].currency,
      hashPurchaseAccessToken(purchaseAccessToken)
    ]
  );

  return {
    book: book.rows[0],
    purchase: purchase.rows[0],
    purchaseAccessToken
  };
}

checkoutRouter.post('/nowpayments', async (req, res, next) => {
  try {
    const body = z.object({
      bookId: z.string().uuid(),
      buyerEmail: z.string().email().optional()
    }).parse(req.body);

    const created = await createPurchase(body.bookId, body.buyerEmail);
    if ('error' in created) return res.status(created.errorStatus).json({ error: created.error });

    const payment = await createNowPayment(
      created.purchase.id,
      created.book.price_cents,
      (created.book.currency || 'USD').toLowerCase(),
      `Readora ebook: ${created.book.title}`
    );

    await query(
      'UPDATE purchases SET btcpay_invoice_id=$1, btcpay_checkout_link=$2 WHERE id=$3',
      [payment.paymentId, payment.paymentUrl, created.purchase.id]
    );

    res.status(201).json({
      provider: 'nowpayments',
      purchaseId: created.purchase.id,
      purchaseAccessToken: created.purchaseAccessToken,
      paymentId: payment.paymentId,
      checkoutLink: payment.paymentUrl,
      paymentUrl: payment.paymentUrl,
      payAddress: payment.payAddress
    });
  } catch (err) {
    next(err);
  }
});

checkoutRouter.post('/btcpay', async (req, res, next) => {
  try {
    const body = z.object({
      bookId: z.string().uuid(),
      buyerEmail: z.string().email().optional()
    }).parse(req.body);

    if (env.USE_NOWPAYMENTS) {
      const created = await createPurchase(body.bookId, body.buyerEmail);
      if ('error' in created) return res.status(created.errorStatus).json({ error: created.error });

      const payment = await createNowPayment(
        created.purchase.id,
        created.book.price_cents,
        (created.book.currency || 'USD').toLowerCase(),
        `Readora ebook: ${created.book.title}`
      );

      await query(
        'UPDATE purchases SET btcpay_invoice_id=$1, btcpay_checkout_link=$2 WHERE id=$3',
        [payment.paymentId, payment.paymentUrl, created.purchase.id]
      );

      return res.status(201).json({
        provider: 'nowpayments',
        purchaseId: created.purchase.id,
        purchaseAccessToken: created.purchaseAccessToken,
        paymentId: payment.paymentId,
        checkoutLink: payment.paymentUrl,
        paymentUrl: payment.paymentUrl,
        payAddress: payment.payAddress
      });
    }

    const created = await createPurchase(body.bookId, body.buyerEmail);
    if ('error' in created) return res.status(created.errorStatus).json({ error: created.error });

    const amount = created.book.price_cents / 100;

    const invoice = await createInvoice({
      amount,
      currency: created.book.currency || env.BTCPAY_CURRENCY,
      orderId: created.purchase.id,
      buyerEmail: body.buyerEmail,
      redirectUrl: `${env.APP_URL}/purchase-success?purchase=${created.purchase.id}`
    });

    await query(
      'UPDATE purchases SET btcpay_invoice_id=$1, btcpay_checkout_link=$2 WHERE id=$3',
      [invoice.id, invoice.checkoutLink, created.purchase.id]
    );

    res.status(201).json({
      provider: env.USE_MOCK_BTCPAY ? 'mock' : 'btcpay',
      purchaseId: created.purchase.id,
      purchaseAccessToken: created.purchaseAccessToken,
      invoiceId: invoice.id,
      checkoutLink: invoice.checkoutLink
    });
  } catch (err) {
    next(err);
  }
});

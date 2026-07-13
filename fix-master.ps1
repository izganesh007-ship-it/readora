$ErrorActionPreference = "Stop"

$ProjectRoot = "C:\Users\comp\Documents\readora (1)\readora"
if (-not (Test-Path (Join-Path $ProjectRoot "package.json"))) {
  $ProjectRoot = (Get-Location).Path
}
if (-not (Test-Path (Join-Path $ProjectRoot "package.json"))) {
  throw "Cannot find package.json. Run this inside the Readora project folder."
}

Set-Location $ProjectRoot

$SrcDir = Join-Path $ProjectRoot "src"
$RoutesDir = Join-Path $SrcDir "routes"
$ServicesDir = Join-Path $SrcDir "services"
$ConfigDir = Join-Path $SrcDir "config"
$MiddlewareDir = Join-Path $SrcDir "middleware"
$PublicDir = Join-Path $ProjectRoot "public"
$ScriptsDir = Join-Path $ProjectRoot "scripts"

New-Item -ItemType Directory -Force -Path $RoutesDir | Out-Null
New-Item -ItemType Directory -Force -Path $ServicesDir | Out-Null
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
New-Item -ItemType Directory -Force -Path $MiddlewareDir | Out-Null
New-Item -ItemType Directory -Force -Path $PublicDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null

$EnvTs = @'
import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(8080),
  APP_URL: z.string().url().default('http://localhost:8080'),
  DATABASE_URL: z.string().min(1),
  COOKIE_SECRET: z.string().min(16).default('dev_cookie_secret_change_me'),
  JWT_SECRET: z.string().min(16).default('dev_jwt_secret_change_me'),
  CORS_ORIGIN: z.string().default('http://localhost:3000'),

  CONFIG_AUTO_UPGRADE: z.coerce.boolean().default(true),
  BTCPAY_MODE: z.enum(['auto', 'mock', 'live', 'nowpayments']).default('auto'),

  STORAGE_DRIVER: z.enum(['auto', 'local', 's3', 'r2']).default('auto'),
  LOCAL_STORAGE_DIR: z.string().default('./storage'),

  BTCPAY_URL: z.string().url().optional(),
  BTCPAY_API_KEY: z.string().optional(),
  BTCPAY_STORE_ID: z.string().optional(),
  BTCPAY_WEBHOOK_SECRET: z.string().optional(),
  BTCPAY_CURRENCY: z.string().default('USD'),

  NOWPAYMENTS_API_KEY: z.string().optional(),
  NOWPAYMENTS_IPN_SECRET: z.string().optional(),

  R2_ENDPOINT: z.string().optional(),
  R2_ACCESS_KEY_ID: z.string().optional(),
  R2_SECRET_ACCESS_KEY: z.string().optional(),
  R2_BUCKET: z.string().optional(),
  R2_REGION: z.string().default('auto'),

  SIGNED_URL_SECONDS: z.coerce.number().default(300),
  DOWNLOAD_TOKEN_HOURS: z.coerce.number().default(24),

  LOGIN_RATE_LIMIT_WINDOW_MIN: z.coerce.number().default(15),
  LOGIN_RATE_LIMIT_MAX: z.coerce.number().default(5),
  API_RATE_LIMIT_WINDOW_MIN: z.coerce.number().default(15),
  API_RATE_LIMIT_MAX: z.coerce.number().default(300)
});

const parsed = schema.parse(process.env);

const hasBtcpayConfig = Boolean(
  parsed.BTCPAY_URL &&
  parsed.BTCPAY_API_KEY &&
  parsed.BTCPAY_STORE_ID &&
  parsed.BTCPAY_WEBHOOK_SECRET
);

const hasNowPaymentsConfig = Boolean(parsed.NOWPAYMENTS_API_KEY);

const hasR2Config = Boolean(
  parsed.R2_ENDPOINT &&
  parsed.R2_ACCESS_KEY_ID &&
  parsed.R2_SECRET_ACCESS_KEY &&
  parsed.R2_BUCKET
);

const useNowPayments =
  parsed.BTCPAY_MODE === 'nowpayments' ||
  (parsed.BTCPAY_MODE === 'auto' && hasNowPaymentsConfig);

const useMockBtcpay = parsed.BTCPAY_MODE === 'mock'
  ? true
  : parsed.BTCPAY_MODE === 'live'
    ? false
    : parsed.BTCPAY_MODE === 'nowpayments'
      ? false
      : !hasBtcpayConfig && !useNowPayments;

const activeStorageDriver = parsed.STORAGE_DRIVER === 'auto'
  ? (hasR2Config ? 's3' : 'local')
  : parsed.STORAGE_DRIVER === 'local' && parsed.CONFIG_AUTO_UPGRADE && hasR2Config
    ? 's3'
    : parsed.STORAGE_DRIVER;

export const env = {
  ...parsed,
  STORAGE_DRIVER_REQUESTED: parsed.STORAGE_DRIVER,
  STORAGE_DRIVER: activeStorageDriver as 'local' | 's3' | 'r2',
  HAS_BTCPAY_CONFIG: hasBtcpayConfig,
  HAS_NOWPAYMENTS_CONFIG: hasNowPaymentsConfig,
  HAS_R2_CONFIG: hasR2Config,
  USE_NOWPAYMENTS: useNowPayments,
  USE_MOCK_BTCPAY: useMockBtcpay
};

export const isProd = env.NODE_ENV === 'production';
'@
Set-Content -Path (Join-Path $ConfigDir "env.ts") -Value $EnvTs -Encoding UTF8

$SecurityTs = @'
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { env, isProd } from '../config/env.js';

export const corsMiddleware = cors({
  origin: env.CORS_ORIGIN.split(',').map(v => v.trim()),
  credentials: true
});

export const helmetMiddleware = helmet({
  contentSecurityPolicy: {
    useDefaults: true,
    directives: {
      "default-src": ["'self'"],
      "script-src": ["'self'", "'unsafe-inline'"],
      "script-src-attr": ["'none'"],
      "style-src": ["'self'", "'unsafe-inline'"],
      "img-src": ["'self'", "data:", "blob:", "https:"],
      "connect-src": ["'self'", "https://api.nowpayments.io", env.BTCPAY_URL || "'self'"],
      "frame-ancestors": ["'none'"]
    }
  },
  hsts: isProd ? { maxAge: 31536000, includeSubDomains: true, preload: true } : false
});

export const apiLimiter = rateLimit({
  windowMs: env.API_RATE_LIMIT_WINDOW_MIN * 60_000,
  limit: env.API_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false
});

export const loginLimiter = rateLimit({
  windowMs: env.LOGIN_RATE_LIMIT_WINDOW_MIN * 60_000,
  limit: env.LOGIN_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many login attempts. Try again later.' }
});
'@
Set-Content -Path (Join-Path $MiddlewareDir "security.ts") -Value $SecurityTs -Encoding UTF8

$NowPaymentsTs = @'
import crypto from 'node:crypto';
import { env } from '../config/env.js';

type NowPaymentsCreatePaymentResponse = {
  payment_id?: string | number;
  payment_status?: string;
  pay_address?: string;
  pay_amount?: number;
  pay_currency?: string;
  price_amount?: number;
  price_currency?: string;
  order_id?: string;
  order_description?: string;
  invoice_url?: string;
  payment_url?: string;
  pay_url?: string;
  payment_link?: string;
  purchase_id?: string;
  [key: string]: unknown;
};

function requireApiKey() {
  if (!env.NOWPAYMENTS_API_KEY) {
    throw new Error('NOWPAYMENTS_API_KEY is not configured');
  }
  return env.NOWPAYMENTS_API_KEY;
}

function sortObject(value: any): any {
  if (Array.isArray(value)) return value.map(sortObject);
  if (value && typeof value === 'object') {
    return Object.keys(value).sort().reduce((acc: any, key) => {
      acc[key] = sortObject(value[key]);
      return acc;
    }, {});
  }
  return value;
}

export function verifyNowPaymentsSignature(body: unknown, signature?: string | string[]) {
  if (!env.NOWPAYMENTS_IPN_SECRET) return true;

  const sig = Array.isArray(signature) ? signature[0] : signature;
  if (!sig) return false;

  const sortedBody = sortObject(body);
  const stringified = JSON.stringify(sortedBody);

  const expected = crypto
    .createHmac('sha512', env.NOWPAYMENTS_IPN_SECRET)
    .update(stringified)
    .digest('hex');

  const a = Buffer.from(String(sig));
  const b = Buffer.from(expected);

  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export async function createPayment(
  orderId: string,
  priceCents: number,
  currency = 'usd',
  orderDescription = 'Readora ebook purchase'
) {
  const apiKey = requireApiKey();
  const priceAmount = Math.max(0, Number(priceCents || 0) / 100);

  const body = {
    price_amount: priceAmount,
    price_currency: currency.toLowerCase(),
    pay_currency: 'btc',
    order_id: orderId,
    order_description: orderDescription,
    ipn_callback_url: `${env.APP_URL.replace(/\/$/, '')}/api/webhooks/nowpayments`
  };

  const response = await fetch('https://api.nowpayments.io/v1/payment', {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'content-type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  const text = await response.text();
  let data: NowPaymentsCreatePaymentResponse;

  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`NOWPayments returned non-JSON response: ${text}`);
  }

  if (!response.ok) {
    const message =
      (data as any).message ||
      (data as any).error ||
      JSON.stringify(data) ||
      `NOWPayments payment failed with status ${response.status}`;
    throw new Error(message);
  }

  const paymentId = String(data.payment_id || data.purchase_id || data.order_id || orderId);
  const payAddress = String(data.pay_address || '');
  const payAmount = data.pay_amount ? String(data.pay_amount) : '';

  const paymentUrl =
    String(data.invoice_url || data.payment_url || data.pay_url || data.payment_link || '') ||
    (payAddress ? `bitcoin:${payAddress}${payAmount ? `?amount=${payAmount}` : ''}` : 'https://nowpayments.io');

  return {
    paymentId,
    paymentUrl,
    payAddress,
    raw: data
  };
}
'@
Set-Content -Path (Join-Path $ServicesDir "nowpayments.ts") -Value $NowPaymentsTs -Encoding UTF8

$CheckoutTs = @'
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
'@
Set-Content -Path (Join-Path $RoutesDir "checkout.ts") -Value $CheckoutTs -Encoding UTF8

$WebhooksTs = @'
import { Router } from 'express';
import { tx } from '../db.js';
import { verifyWebhook } from '../services/btcpay.js';
import { verifyNowPaymentsSignature } from '../services/nowpayments.js';
import { createDownloadLink } from '../services/downloadToken.js';
import { audit } from '../services/audit.js';

export const webhooksRouter = Router();

async function markPurchasePaid(input: {
  purchaseId?: string;
  providerPaymentId?: string;
  provider: string;
  payload: unknown;
  ip?: string;
}) {
  await tx(async client => {
    const p = input.purchaseId
      ? await client.query('SELECT * FROM purchases WHERE id=$1 FOR UPDATE', [input.purchaseId])
      : await client.query('SELECT * FROM purchases WHERE btcpay_invoice_id=$1 FOR UPDATE', [input.providerPaymentId]);

    if (!p.rowCount) return;

    const purchase = p.rows[0];

    if (purchase.status !== 'PAID') {
      await client.query(
        `UPDATE purchases
         SET status='PAID', paid_at=now()
         WHERE id=$1`,
        [purchase.id]
      );
    }

    const existing = await client.query(
      `SELECT id FROM download_links
       WHERE purchase_id=$1 AND status IN ('ACTIVE','USED') LIMIT 1`,
      [purchase.id]
    );

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

webhooksRouter.post('/btcpay', async (req: any, res, next) => {
  try {
    const sig = req.get('BTCPay-Sig') || req.get('btcpay-sig');
    const raw = req.rawBody || Buffer.from(JSON.stringify(req.body || {}));

    if (!verifyWebhook(raw, sig)) {
      return res.status(401).json({ error: 'Invalid webhook signature' });
    }

    const event = req.body;
    const invoiceId = event.invoiceId || event.invoice?.id;
    const type = event.type || event.event;

    if (!invoiceId) return res.status(202).json({ ok: true });

    if (['InvoiceSettled', 'InvoicePaymentSettled', 'InvoiceProcessing'].includes(type)) {
      await markPurchasePaid({
        providerPaymentId: invoiceId,
        provider: 'btcpay',
        payload: event,
        ip: req.ip
      });
    }

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

webhooksRouter.post('/nowpayments', async (req, res, next) => {
  try {
    const signature =
      req.get('x-nowpayments-sig') ||
      req.get('X-NOWPAYMENTS-SIG') ||
      req.get('x-nowpayments-signature');

    if (!verifyNowPaymentsSignature(req.body, signature || undefined)) {
      return res.status(401).json({ error: 'Invalid NOWPayments IPN signature' });
    }

    const payload: any = req.body || {};
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
  } catch (err) {
    next(err);
  }
});
'@
Set-Content -Path (Join-Path $RoutesDir "webhooks.ts") -Value $WebhooksTs -Encoding UTF8

$PurchasesTs = @'
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
'@
Set-Content -Path (Join-Path $RoutesDir "purchases.ts") -Value $PurchasesTs -Encoding UTF8

$AdminTs = @'
import { Router } from 'express';
import argon2 from 'argon2';
import crypto from 'node:crypto';
import path from 'node:path';
import fs from 'node:fs/promises';
import multer from 'multer';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { z } from 'zod';
import { query } from '../db.js';
import { loginLimiter } from '../middleware/security.js';
import { requireAdmin, signAdminSession } from '../middleware/auth.js';
import { audit } from '../services/audit.js';
import { env, isProd } from '../config/env.js';
import { localPathForKey } from '../services/storage.js';

export const adminRouter = Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 150 * 1024 * 1024 }
});

const s3 = new S3Client({
  region: env.R2_REGION,
  endpoint: env.R2_ENDPOINT,
  forcePathStyle: true,
  credentials: env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY ? {
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY
  } : undefined
});

function safeFileName(name: string) {
  return name.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '') || 'file';
}

function buildFileKey(kind: string, originalName: string) {
  const safe = safeFileName(originalName);
  const ext = path.extname(safe);
  const prefix = kind === 'cover' ? 'cover' : 'ebook';
  return `books/${prefix}-${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
}

adminRouter.post('/login', loginLimiter, async (req, res, next) => {
  try {
    const body = z.object({
      email: z.string().email(),
      password: z.string().min(8),
      totp: z.string().optional()
    }).parse(req.body);

    const out = await query(
      'SELECT id,email,password_hash,role,locked_until FROM admins WHERE email=$1',
      [body.email]
    );

    if (!out.rowCount) return res.status(401).json({ error: 'Invalid credentials' });

    const admin = out.rows[0];

    if (admin.locked_until && new Date(admin.locked_until) > new Date()) {
      return res.status(423).json({ error: 'Account temporarily locked' });
    }

    const ok = await argon2.verify(admin.password_hash, body.password);

    if (!ok) {
      await query(
        `UPDATE admins
         SET failed_attempts=failed_attempts+1,
             locked_until=CASE WHEN failed_attempts>=4 THEN now()+interval '15 minutes' ELSE locked_until END
         WHERE id=$1`,
        [admin.id]
      );
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    await query(
      'UPDATE admins SET failed_attempts=0, locked_until=NULL, last_login_at=now() WHERE id=$1',
      [admin.id]
    );

    const token = signAdminSession({ adminId: admin.id, role: admin.role });

    res.cookie('admin_session', token, {
      httpOnly: true,
      secure: isProd,
      sameSite: 'lax',
      maxAge: 2 * 60 * 60 * 1000
    });

    await audit('ADMIN_LOGIN', { adminId: admin.id, ip: req.ip });

    res.json({
      ok: true,
      token,
      role: admin.role
    });
  } catch (err) {
    next(err);
  }
});

adminRouter.post('/logout', (_req, res) => {
  res.clearCookie('admin_session');
  res.json({ ok: true });
});

adminRouter.post('/uploads', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), upload.single('file'), async (req, res, next) => {
  try {
    const file = req.file;
    if (!file) return res.status(400).json({ error: 'No file uploaded. Use multipart field name: file' });

    const body = z.object({
      kind: z.enum(['cover', 'ebook']).default('ebook')
    }).parse(req.body);

    if (body.kind === 'cover' && !file.mimetype.startsWith('image/')) {
      return res.status(400).json({ error: 'Cover upload must be an image' });
    }

    if (body.kind === 'ebook' && !/\.(pdf|epub)$/i.test(file.originalname)) {
      return res.status(400).json({ error: 'Ebook upload must be .pdf or .epub' });
    }

    const key = buildFileKey(body.kind, file.originalname);

    if (env.STORAGE_DRIVER === 'local') {
      const full = localPathForKey(key);
      await fs.mkdir(path.dirname(full), { recursive: true });
      await fs.writeFile(full, file.buffer);
    } else {
      if (!env.R2_BUCKET) return res.status(500).json({ error: 'R2_BUCKET is not configured' });

      await s3.send(new PutObjectCommand({
        Bucket: env.R2_BUCKET,
        Key: key,
        Body: file.buffer,
        ContentType: file.mimetype || 'application/octet-stream'
      }));
    }

    await audit('ADMIN_FILE_UPLOADED', {
      adminId: req.admin?.adminId,
      entityType: body.kind,
      entityId: key,
      ip: req.ip,
      metadata: {
        originalName: file.originalname,
        mimetype: file.mimetype,
        size: file.size,
        storageDriver: env.STORAGE_DRIVER
      }
    });

    res.status(201).json({
      key,
      kind: body.kind,
      originalName: file.originalname,
      contentType: file.mimetype,
      size: file.size
    });
  } catch (err) {
    next(err);
  }
});

adminRouter.get('/analytics', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (_req, res, next) => {
  try {
    const [books, revenue, sales, downloads, views, trending] = await Promise.all([
      query('SELECT count(*)::int AS value FROM books'),
      query("SELECT COALESCE(sum(amount_cents),0)::int AS value FROM purchases WHERE status='PAID'"),
      query("SELECT count(*)::int AS value FROM purchases WHERE status='PAID'"),
      query("SELECT count(*)::int AS value FROM download_links WHERE status='USED'"),
      query('SELECT count(*)::int AS value FROM book_views'),
      query(`
        SELECT b.title,b.slug,count(v.id)::int AS views
        FROM books b
        LEFT JOIN book_views v ON v.book_id=b.id
        GROUP BY b.id
        ORDER BY views DESC
        LIMIT 10
      `)
    ]);

    res.json({
      totalBooks: books.rows[0].value,
      revenueCents: revenue.rows[0].value,
      sales: sales.rows[0].value,
      downloads: downloads.rows[0].value,
      views: views.rows[0].value,
      trending: trending.rows
    });
  } catch (err) {
    next(err);
  }
});

adminRouter.post('/books', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (req, res, next) => {
  try {
    const body = z.object({
      title: z.string().min(1),
      slug: z.string().min(1),
      author: z.string().min(1),
      categoryId: z.string().uuid().optional().nullable(),
      description: z.string().min(1),
      previewText: z.string().optional().nullable(),
      access: z.enum(['FREE', 'PAID']),
      priceCents: z.number().int().min(0),
      coverKey: z.string().optional().nullable(),
      epubKey: z.string().optional().nullable(),
      pdfKey: z.string().optional().nullable(),
      readerFormat: z.enum(['CHAPTERS', 'TXT', 'HTML', 'PDF']).default('CHAPTERS'),
      readerContent: z.string().optional().nullable(),
      readerContentKey: z.string().optional().nullable(),
      allowFreeDownload: z.boolean().default(false),
      featured: z.boolean().default(false)
    }).parse(req.body);

    const out = await query(
      `INSERT INTO books(
        title,slug,author,category_id,description,preview_text,access,price_cents,
        cover_key,epub_key,pdf_key,reader_format,reader_content,reader_content_key,
        allow_free_download,featured,published_at
      )
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,now())
      RETURNING id,slug`,
      [
        body.title,
        body.slug,
        body.author,
        body.categoryId || null,
        body.description,
        body.previewText || null,
        body.access,
        body.priceCents,
        body.coverKey || null,
        body.epubKey || null,
        body.pdfKey || null,
        body.readerFormat,
        body.readerContent || null,
        body.readerContentKey || null,
        body.allowFreeDownload,
        body.featured
      ]
    );

    await audit('BOOK_CREATED', {
      adminId: req.admin?.adminId,
      entityType: 'book',
      entityId: out.rows[0].id,
      ip: req.ip
    });

    res.status(201).json({ data: out.rows[0] });
  } catch (err) {
    next(err);
  }
});
'@
Set-Content -Path (Join-Path $RoutesDir "admin.ts") -Value $AdminTs -Encoding UTF8

$ExistingIndexPath = Join-Path $PublicDir "index.html"
$ExistingPreviewPath = Join-Path $ProjectRoot "preview.html"
$ExistingHtml = ""

if (Test-Path $ExistingIndexPath) {
  $ExistingHtml = Get-Content $ExistingIndexPath -Raw
} elseif (Test-Path $ExistingPreviewPath) {
  $ExistingHtml = Get-Content $ExistingPreviewPath -Raw
}

$StyleBlock = ""
if ($ExistingHtml -match "(?s)<style>.*?</style>") {
  $StyleBlock = $Matches[0]
} else {
  $StyleBlock = @'
<style>
:root{--bg:#050505;--panel:#121214;--text:#f8f8f8;--muted:#a5a5ad;--red:#e50914;--gold:#f6c85f;--green:#33d17a;--shadow:0 25px 70px rgba(0,0,0,.65);--header:74px}
*{box-sizing:border-box}body{margin:0;background:#050505;color:#f8f8f8;font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif}
.header{height:var(--header);position:sticky;top:0;z-index:80;display:flex;gap:18px;align-items:center;padding:0 36px;background:rgba(5,5,5,.9);backdrop-filter:blur(24px);border-bottom:1px solid rgba(255,255,255,.1)}
.brand{font-size:30px;font-weight:950}.brand-mark{background:var(--red);border-radius:9px;padding:5px 10px;margin-right:8px}.nav{display:flex;gap:8px;flex:1}.nav a{padding:10px 12px;border-radius:999px;color:#ddd;text-decoration:none;font-weight:800}.nav a:hover{background:rgba(255,255,255,.1)}
.search input,.control{background:#121216;color:#fff;border:1px solid rgba(255,255,255,.14);border-radius:14px;padding:12px}.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;border:0;border-radius:999px;padding:12px 18px;background:#27272a;color:#fff;font-weight:950;cursor:pointer;text-decoration:none}.btn.primary{background:linear-gradient(135deg,#e50914,#ff2330)}
.browse-shell,.admin,.checkout,.details{padding:34px 48px 64px}.page-title{font-size:60px;letter-spacing:-3px}.lead{color:#c9c9d0;line-height:1.6}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:18px}.book-card{background:#141418;border:1px solid rgba(255,255,255,.1);border-radius:22px;overflow:hidden;cursor:pointer}.book-cover{height:240px;padding:16px;background:linear-gradient(145deg,#3b0005,#e50914,#111);display:flex;flex-direction:column;justify-content:space-between}.mini-title{font-size:24px;font-weight:950}.card-body{padding:12px}.panel{background:#111114;border:1px solid rgba(255,255,255,.1);border-radius:24px;padding:22px;margin-top:22px}.footer{padding:34px 48px;border-top:1px solid rgba(255,255,255,.08);color:#aaa}.toast{position:fixed;right:22px;bottom:22px;z-index:200;display:grid;gap:10px}.toast-item{background:#151518;border:1px solid rgba(255,255,255,.1);border-left:4px solid var(--red);color:#fff;border-radius:14px;padding:13px 15px;box-shadow:var(--shadow)}
</style>
'@
}

$IndexTemplate = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Readora — Premium Ebook Marketplace</title>
  <meta name="description" content="Readora is a premium Netflix-style ebook marketplace for discovering, buying, reading, and securely downloading ebooks." />
  <meta name="theme-color" content="#050505" />
  __STYLE_BLOCK__
</head>
<body>
<div class="app">
  <header class="header">
    <div class="traffic" aria-hidden="true"><i></i><i></i><i></i></div>
    <a class="brand" href="#home" aria-label="Readora home"><span class="brand-mark">R</span><span>Readora</span></a>
    <nav class="nav" id="nav">
      <a href="#home" data-route="home">Home</a>
      <a href="#browse" data-route="browse">Browse</a>
      <a href="#wishlist" data-route="wishlist">Wishlist</a>
      <a href="#admin" data-route="admin">Admin</a>
    </nav>
    <form class="search" id="globalSearch">
      <input id="searchInput" placeholder="Search books, authors, tags..." autocomplete="off" />
    </form>
    <a class="icon-btn" href="#wishlist" title="Wishlist" style="position:relative">&#9829;<span class="badge-count" id="wishCount">0</span></a>
    <button class="icon-btn menu-btn" id="menuBtn" type="button" aria-label="Open menu">☰</button>
  </header>

  <nav class="mobile-nav" id="mobileNav">
    <a href="#home">Home</a>
    <a href="#browse">Browse</a>
    <a href="#wishlist">Wishlist</a>
    <a href="#admin">Admin</a>
  </nav>

  <main id="view"></main>

  <footer class="footer">
    <div><b>Readora</b> — premium ebook marketplace with Backblaze B2 storage, crypto checkout, and one-time downloads.</div>
    <div>
      <a href="#about">About</a>
      <a href="#contact">Contact</a>
      <a href="#privacy">Privacy</a>
      <a href="#terms">Terms</a>
    </div>
  </footer>

  <div class="toast" id="toast"></div>
</div>

<script>
(function () {
  console.log('[Readora] SPA loaded');

  const state = {
    categories: [],
    adminToken: localStorage.getItem('readora_admin_token') || '',
    wishlist: JSON.parse(localStorage.getItem('readora_wishlist') || '[]'),
    pendingPurchase: JSON.parse(localStorage.getItem('readora_pending_purchase') || 'null'),
    paymentPollTimer: null
  };

  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));

  const money = cents => Number(cents || 0) === 0 ? 'Free' : '$' + (Number(cents || 0) / 100).toFixed(2);
  const slugify = s => String(s || '').toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');

  function escapeHtml(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function toast(msg) {
    console.log('[Readora]', msg);
    const t = $('#toast');
    if (!t) return alert(msg);
    const el = document.createElement('div');
    el.className = 'toast-item';
    el.textContent = msg;
    t.appendChild(el);
    setTimeout(() => el.remove(), 3500);
  }

  function setWish() {
    localStorage.setItem('readora_wishlist', JSON.stringify(state.wishlist));
    const c = $('#wishCount');
    if (c) c.textContent = state.wishlist.length;
  }

  function isWished(slug) {
    return state.wishlist.includes(slug);
  }

  function toggleWish(slug) {
    state.wishlist = isWished(slug) ? state.wishlist.filter(x => x !== slug) : [slug, ...state.wishlist];
    setWish();
    render();
  }

  async function api(path, options = {}) {
    console.log('[Readora API]', options.method || 'GET', path);

    const headers = Object.assign({ 'Content-Type': 'application/json' }, options.headers || {});
    if (state.adminToken && state.adminToken !== 'cookie') headers.Authorization = 'Bearer ' + state.adminToken;

    const res = await fetch(path, Object.assign({
      credentials: 'include',
      headers
    }, options));

    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }

    console.log('[Readora API response]', res.status, path, data);

    if (!res.ok) {
      const msg = data && data.error ? data.error : ('Request failed: ' + res.status);
      throw new Error(msg);
    }

    return data;
  }

  async function uploadAdminFile(file, kind) {
    if (!file) return null;

    console.log('[Readora] uploadAdminFile', kind, file.name);

    const formData = new FormData();
    formData.append('file', file);
    formData.append('kind', kind);

    const headers = {};
    if (state.adminToken && state.adminToken !== 'cookie') headers.Authorization = 'Bearer ' + state.adminToken;

    const res = await fetch('/api/admin/uploads', {
      method: 'POST',
      credentials: 'include',
      headers,
      body: formData
    });

    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }

    console.log('[Readora upload response]', res.status, data);

    if (!res.ok) {
      const msg = data && data.error ? data.error : ('Upload failed: ' + res.status);
      throw new Error(msg);
    }

    return data.key;
  }

  function loading(title = 'Loading...') {
    return `<div class="page browse-shell"><div class="eyebrow">Readora</div><h1 class="page-title">${escapeHtml(title)}</h1><p class="lead">Please wait.</p></div>`;
  }

  function errorView(err) {
    console.error('[Readora Error]', err);
    return `<div class="page browse-shell"><div class="eyebrow">Error</div><h1 class="page-title">Something went wrong</h1><p class="lead">${escapeHtml(err.message || err)}</p><div class="panel"><p>Open DevTools Console and Railway logs for details.</p></div></div>`;
  }

  function gradientFor(book) {
    const seed = (book.slug || book.title || 'readora').length % 6;
    return [
      'linear-gradient(145deg,#3b0005,#e50914 55%,#111)',
      'linear-gradient(145deg,#092036,#2563eb 58%,#050505)',
      'linear-gradient(145deg,#2b1700,#f7931a 58%,#121212)',
      'linear-gradient(145deg,#14002e,#7c3aed 55%,#030712)',
      'linear-gradient(145deg,#051b11,#10b981 58%,#0b0b0d)',
      'linear-gradient(145deg,#0a0a0a,#991b1b 55%,#3f0a0a)'
    ][seed];
  }

  function normalizeBook(b) {
    return {
      id: b.id,
      slug: b.slug,
      title: b.title,
      author: b.author,
      description: b.description || '',
      access: b.access,
      free: b.access === 'FREE',
      priceCents: b.price_cents ?? b.priceCents ?? 0,
      coverKey: b.cover_key ?? b.coverKey,
      rating: b.rating || 0,
      category: b.category || b.category_name || '',
      categorySlug: b.category_slug || ''
    };
  }

  function cover(book, cls = 'book-cover') {
    return `<div class="${cls}" style="--cover-gradient:${gradientFor(book)};background:${gradientFor(book)}">
      <div class="cover-mark">READORA</div>
      <div class="mini-title">${escapeHtml(book.title)}</div>
      <div class="mini-author">${escapeHtml(book.author || '')}</div>
    </div>`;
  }

  function card(raw) {
    const book = normalizeBook(raw);
    return `<article class="book-card" data-action="details" data-slug="${escapeHtml(book.slug)}">
      <button class="heart ${isWished(book.slug) ? 'active' : ''}" type="button" data-action="wishlist" data-slug="${escapeHtml(book.slug)}">&#9829;</button>
      <span class="price-badge ${book.free ? 'free' : 'paid'}">${book.free ? 'FREE' : 'PAID'}</span>
      ${cover(book)}
      <div class="card-body">
        <div class="card-title">${escapeHtml(book.title)}</div>
        <div class="card-meta"><span>${escapeHtml(book.author || '')}</span><span class="rating">★ ${Number(book.rating || 0)}</span></div>
        <div class="card-meta" style="margin-top:5px"><span>${escapeHtml(book.category || '')}</span><b>${money(book.priceCents)}</b></div>
      </div>
    </article>`;
  }

  function row(title, subtitle, items) {
    return `<section class="section">
      <div class="section-head">
        <div><h2 class="section-title">${escapeHtml(title)}</h2><p class="section-sub">${escapeHtml(subtitle)}</p></div>
        <a class="btn small ghost" href="#browse">See all</a>
      </div>
      <div class="rail">${items.length ? items.map(card).join('') : '<div class="empty">No books yet. Add books in admin.</div>'}</div>
    </section>`;
  }

  async function ensureCategories() {
    if (state.categories.length) return state.categories;
    const out = await api('/api/categories');
    state.categories = out.data || [];
    return state.categories;
  }

  async function renderHome() {
    $('#view').innerHTML = loading('Loading Readora...');
    try {
      const out = await api('/api/home');
      const featured = (out.featured || []).map(normalizeBook);
      const trending = (out.trending || []).map(normalizeBook);
      const newest = (out.newest || []).map(normalizeBook);
      const hero = featured[0] || trending[0] || newest[0];

      if (!hero) {
        $('#view').innerHTML = `<div class="page browse-shell">
          <div class="eyebrow">Readora</div>
          <h1 class="page-title">No books found</h1>
          <p class="lead">Your database has no books yet. Login to admin and add books.</p>
          <div class="actions"><a class="btn primary" href="#admin">Open Admin</a></div>
        </div>`;
        return;
      }

      $('#view').innerHTML = `<div class="page">
        <section class="hero" style="--hero-gradient:${gradientFor(hero)}">
          <div class="hero-bg"></div>
          <div>
            <div class="eyebrow">Featured Read</div>
            <h1>${escapeHtml(hero.title)}</h1>
            <p>${escapeHtml(hero.description || '')}</p>
            <div class="hero-meta">
              <span class="pill red">${hero.free ? 'Free to read' : 'Premium paid ebook'}</span>
              <span class="pill">${escapeHtml(hero.author || '')}</span>
              <span class="pill">${escapeHtml(hero.category || '')}</span>
              <span class="pill rating">★ ${Number(hero.rating || 0)}</span>
              <span class="pill">${money(hero.priceCents)}</span>
            </div>
            <div class="actions">
              <a class="btn primary" href="${hero.free ? '#reader/' + hero.slug : '#checkout/' + hero.slug}">${hero.free ? 'Read Free' : 'Pay with Crypto'}</a>
              <a class="btn ghost" href="#details/${hero.slug}">View Details</a>
              <button class="btn ghost" type="button" data-action="wishlist" data-slug="${escapeHtml(hero.slug)}">&#9829; Wishlist</button>
            </div>
          </div>
          <div class="hero-card">
            <div class="cover-xl" style="--cover-gradient:${gradientFor(hero)};background:${gradientFor(hero)}">
              <div class="cover-mark">READORA</div>
              <div class="cover-title">${escapeHtml(hero.title)}</div>
              <div class="cover-author">${escapeHtml(hero.author || '')}</div>
            </div>
          </div>
        </section>
        ${row('Trending Books', 'Most viewed and purchased this week', trending)}
        ${row('New Releases', 'Fresh drops from your database', newest)}
        ${row('Featured Books', 'Managed by the admin panel', featured)}
      </div>`;
    } catch (err) {
      $('#view').innerHTML = errorView(err);
    }
  }

  async function renderBrowse(params = {}) {
    $('#view').innerHTML = loading('Loading catalog...');
    try {
      const categories = await ensureCategories();
      const qs = new URLSearchParams();
      if (params.q) qs.set('q', params.q);
      if (params.category && params.category !== 'all') qs.set('category', params.category);
      if (params.access && params.access !== 'all') qs.set('access', params.access);
      if (params.sort) qs.set('sort', params.sort);

      const out = await api('/api/books' + (qs.toString() ? '?' + qs.toString() : ''));
      const books = out.data || [];

      $('#view').innerHTML = `<div class="page browse-shell">
        <div class="eyebrow">Catalog</div>
        <h1 class="page-title">Browse all books</h1>
        <p class="lead">Search, filter, and sort books directly from PostgreSQL.</p>
        <form class="filters" id="browseForm">
          <input class="control" id="bq" name="q" value="${escapeHtml(params.q || '')}" placeholder="Search title, author, tags..." />
          <select class="control" id="bc" name="category">
            <option value="all">All categories</option>
            ${categories.map(c => `<option value="${escapeHtml(c.slug)}" ${params.category === c.slug ? 'selected' : ''}>${escapeHtml(c.name)}</option>`).join('')}
          </select>
          <select class="control" id="ba" name="access">
            <option value="all">All access</option>
            <option value="FREE" ${params.access === 'FREE' ? 'selected' : ''}>Free only</option>
            <option value="PAID" ${params.access === 'PAID' ? 'selected' : ''}>Paid only</option>
          </select>
          <select class="control" id="bs" name="sort">
            <option value="popularity" ${params.sort === 'popularity' ? 'selected' : ''}>Sort: Popularity</option>
            <option value="newest" ${params.sort === 'newest' ? 'selected' : ''}>Sort: Newest</option>
            <option value="price" ${params.sort === 'price' ? 'selected' : ''}>Sort: Price</option>
            <option value="rating" ${params.sort === 'rating' ? 'selected' : ''}>Sort: Rating</option>
          </select>
          <button class="btn primary" type="submit">Apply</button>
        </form>
        <div class="grid">${books.length ? books.map(card).join('') : '<div class="empty">No books match your filters.</div>'}</div>
      </div>`;
    } catch (err) {
      $('#view').innerHTML = errorView(err);
    }
  }

  async function renderDetails(slug) {
    $('#view').innerHTML = loading('Loading book...');
    try {
      const out = await api('/api/books/' + encodeURIComponent(slug));
      const book = normalizeBook(out.data);
      const tags = out.data.tags || [];

      $('#view').innerHTML = `<div class="page details">
        <div class="details-wrap">
          <aside class="details-cover">${cover(book, 'cover-detail')}</aside>
          <section>
            <div class="eyebrow">Book Details</div>
            <h1 class="detail-title">${escapeHtml(book.title)}</h1>
            <div class="detail-meta">
              <span class="pill red">${book.free ? 'Free / Read Online' : 'Paid / Purchase Required'}</span>
              <span class="pill">Author: ${escapeHtml(book.author || '')}</span>
              <span class="pill">${escapeHtml(book.category || '')}</span>
              <span class="pill rating">★ ${Number(book.rating || 0)}</span>
              <span class="pill">${money(book.priceCents)}</span>
            </div>
            <p class="detail-desc">${escapeHtml(book.description || '')}</p>
            <div class="tags">${tags.map(t => `<span class="tag">#${escapeHtml(t)}</span>`).join('')}</div>
            <div class="actions">
              <a class="btn primary" href="${book.free ? '#reader/' + book.slug : '#checkout/' + book.slug}">${book.free ? 'Read Online' : 'Pay with Crypto'}</a>
              <button class="btn ghost" type="button" data-action="wishlist" data-slug="${escapeHtml(book.slug)}">&#9829; ${isWished(book.slug) ? 'Remove Wishlist' : 'Add Wishlist'}</button>
              <a class="btn ghost" href="#browse">Back to Browse</a>
            </div>
          </section>
        </div>
      </div>`;
    } catch (err) {
      $('#view').innerHTML = errorView(err);
    }
  }

  async function renderReader(slug) {
    $('#view').innerHTML = loading('Opening reader...');
    try {
      const out = await api('/api/reader/' + encodeURIComponent(slug));
      const b = out.book;
      let content = '';

      if (out.mode === 'PDF') {
        content = `<iframe src="${out.pdfUrl}" style="width:100%;height:75vh;border:0;border-radius:18px;background:#fff"></iframe>`;
      } else if (out.mode === 'HTML') {
        content = `<div class="reader-content">${out.content || ''}</div>`;
      } else if (out.mode === 'TXT') {
        content = `<pre class="reader-content" style="white-space:pre-wrap">${escapeHtml(out.content || '')}</pre>`;
      } else {
        const chapters = out.chapters || [];
        content = chapters.length ? chapters.map(ch => `<h2>${escapeHtml(ch.title)}</h2><p>${escapeHtml(ch.content)}</p>`).join('') : '<p>No chapters found.</p>';
      }

      $('#view').innerHTML = `<div class="page reader">
        <aside class="reader-side">
          <div class="eyebrow">Built-in Reader</div>
          <h2>${escapeHtml(b.title)}</h2>
          <p class="section-sub">${escapeHtml(b.author || '')}</p>
          <a class="btn ghost" href="#details/${b.slug}">Back to details</a>
        </aside>
        <section class="reader-main">
          <article class="reader-book">
            <h1>${escapeHtml(b.title)}</h1>
            ${content}
          </article>
        </section>
      </div>`;
    } catch (err) {
      $('#view').innerHTML = errorView(err);
    }
  }

  function renderWishlist() {
    $('#view').innerHTML = `<div class="page browse-shell">
      <div class="eyebrow">Wishlist</div>
      <h1 class="page-title">Your Wishlist</h1>
      <p class="lead">Stored locally in your browser.</p>
      <div class="panel">
        ${state.wishlist.length ? state.wishlist.map(slug => `<p><a href="#details/${escapeHtml(slug)}">${escapeHtml(slug)}</a></p>`).join('') : '<p>Your wishlist is empty.</p>'}
      </div>
    </div>`;
  }

  async function renderCheckout(slug) {
    $('#view').innerHTML = loading('Preparing crypto checkout...');
    try {
      const out = await api('/api/books/' + encodeURIComponent(slug));
      const book = normalizeBook(out.data);

      $('#view').innerHTML = `<div class="page checkout">
        <div class="eyebrow">Crypto Checkout</div>
        <h1 class="page-title">Pay with Crypto</h1>
        <div class="checkout-card">
          <div>${cover(book, 'cover-detail')}</div>
          <div>
            <h2>${escapeHtml(book.title)}</h2>
            <p class="lead">After payment is confirmed by NOWPayments webhook, Readora will unlock a one-time download token.</p>
            <div class="status-box">
              <div class="status-line"><span class="pulse"></span><b>${money(book.priceCents)}</b></div>
              <div class="status-line">Pay currency: BTC via NOWPayments.</div>
            </div>
            <div class="actions">
              <button class="btn primary" type="button" data-action="start-checkout" data-book-id="${escapeHtml(book.id)}">Pay with Crypto</button>
              <a class="btn ghost" href="#details/${book.slug}">Cancel</a>
            </div>
            <div id="checkoutResult"></div>
          </div>
        </div>
      </div>`;

      if (state.pendingPurchase && state.pendingPurchase.slug === slug) {
        showPendingPayment(state.pendingPurchase);
        startPaymentPolling(state.pendingPurchase);
      }
    } catch (err) {
      $('#view').innerHTML = errorView(err);
    }
  }

  function showPendingPayment(p) {
    const box = $('#checkoutResult');
    if (!box) return;

    box.innerHTML = `<div class="panel">
      <h3>Payment Created</h3>
      <p>Provider: ${escapeHtml(p.provider || 'crypto')}</p>
      <p>Purchase ID: ${escapeHtml(p.purchaseId || '')}</p>
      ${p.payAddress ? `<p>Pay address:</p><div class="token">${escapeHtml(p.payAddress)}</div>` : ''}
      <p>Status: <span id="paymentStatusText">Waiting for payment confirmation...</span></p>
      <div class="actions">
        <a class="btn primary" href="${escapeHtml(p.checkoutLink || '#')}" target="_blank" rel="noopener">Open Payment Page</a>
        <button class="btn ghost" type="button" data-action="poll-payment">Check Payment Status</button>
      </div>
      <div id="downloadTokenBox"></div>
    </div>`;
  }

  async function startCheckout(bookId) {
    const box = $('#checkoutResult');
    if (box) box.innerHTML = '<div class="panel"><p>Creating crypto payment...</p></div>';

    try {
      const out = await api('/api/checkout/nowpayments', {
        method: 'POST',
        body: JSON.stringify({ bookId })
      });

      const currentRoute = parseRoute();
      const slug = currentRoute.path.split('/')[1];

      const pending = {
        provider: out.provider || 'nowpayments',
        purchaseId: out.purchaseId,
        purchaseAccessToken: out.purchaseAccessToken,
        checkoutLink: out.checkoutLink || out.paymentUrl,
        payAddress: out.payAddress || '',
        slug
      };

      state.pendingPurchase = pending;
      localStorage.setItem('readora_pending_purchase', JSON.stringify(pending));

      showPendingPayment(pending);

      if (pending.checkoutLink) {
        window.open(pending.checkoutLink, '_blank', 'noopener,noreferrer');
      }

      startPaymentPolling(pending);
    } catch (err) {
      if (box) box.innerHTML = `<div class="panel"><p>${escapeHtml(err.message)}</p></div>`;
    }
  }

  function startPaymentPolling(pending) {
    if (state.paymentPollTimer) clearInterval(state.paymentPollTimer);
    pollPaymentStatus(pending);
    state.paymentPollTimer = setInterval(() => pollPaymentStatus(pending), 5000);
  }

  async function pollPaymentStatus(pending) {
    const statusText = $('#paymentStatusText');

    try {
      const out = await api(`/api/purchases/${encodeURIComponent(pending.purchaseId)}?accessToken=${encodeURIComponent(pending.purchaseAccessToken)}`);
      const status = out.data && out.data.status ? out.data.status : 'PENDING';

      if (statusText) statusText.textContent = status;

      if (status === 'PAID') {
        if (state.paymentPollTimer) clearInterval(state.paymentPollTimer);
        await unlockDownloadToken(pending);
      }
    } catch (err) {
      if (statusText) statusText.textContent = err.message;
    }
  }

  async function unlockDownloadToken(pending) {
    const box = $('#downloadTokenBox');
    if (box) box.innerHTML = '<p>Creating one-time download token...</p>';

    try {
      const out = await api(`/api/purchases/${encodeURIComponent(pending.purchaseId)}/download-token`, {
        method: 'POST',
        body: JSON.stringify({ accessToken: pending.purchaseAccessToken })
      });

      localStorage.removeItem('readora_pending_purchase');
      state.pendingPurchase = null;

      if (box) {
        box.innerHTML = `<div class="panel">
          <h3>Payment Confirmed</h3>
          <p>Your one-time download token is ready. It expires after first use or after 24 hours.</p>
          <div class="token">${escapeHtml(out.token)}</div>
          <div class="actions">
            <button class="btn primary" type="button" data-action="redeem-download" data-token="${escapeHtml(out.token)}">Download Once</button>
          </div>
        </div>`;
      }
    } catch (err) {
      if (box) box.innerHTML = `<p>${escapeHtml(err.message)}</p>`;
    }
  }

  async function redeemDownload(token) {
    try {
      const out = await api('/api/downloads/' + encodeURIComponent(token) + '/redeem', {
        method: 'POST',
        body: JSON.stringify({})
      });

      if (out.signedUrl) {
        window.open(out.signedUrl, '_blank', 'noopener,noreferrer');
      }
    } catch (err) {
      toast(err.message);
    }
  }

  async function renderAdmin() {
    if (!state.adminToken) {
      $('#view').innerHTML = `<div class="page admin">
        <div class="login-box">
          <div class="eyebrow">Secure Admin Login</div>
          <h1>Admin Panel</h1>
          <p class="section-sub">Use the admin account created with npm run admin:create.</p>
          <form id="adminLoginForm">
            <input class="control" id="adminEmail" name="email" type="email" placeholder="Admin email" autocomplete="username" style="width:100%;margin:8px 0" required />
            <input class="control" id="adminPass" name="password" type="password" placeholder="Admin password" autocomplete="current-password" style="width:100%;margin:8px 0 16px" required />
            <button class="btn primary" id="adminLoginButton" type="submit">Login</button>
          </form>
          <div id="adminLoginDebug" class="section-sub" style="margin-top:12px"></div>
        </div>
      </div>`;
      return;
    }

    $('#view').innerHTML = loading('Loading dashboard...');

    try {
      const [analytics, categoriesOut] = await Promise.all([
        api('/api/admin/analytics'),
        api('/api/categories')
      ]);

      state.categories = categoriesOut.data || [];

      $('#view').innerHTML = `<div class="page admin">
        <div class="eyebrow">Admin Dashboard</div>
        <h1 class="page-title">Readora Control Room</h1>
        <div class="admin-layout">
          <aside class="admin-menu">
            <button class="active" type="button">Dashboard</button>
            <button type="button" data-action="logout-admin">Logout</button>
          </aside>
          <section>
            <div class="metrics">
              <div class="metric"><b>${analytics.totalBooks || 0}</b><span>Total Books</span></div>
              <div class="metric"><b>$${((analytics.revenueCents || 0) / 100).toFixed(2)}</b><span>Revenue</span></div>
              <div class="metric"><b>${analytics.sales || 0}</b><span>Sales</span></div>
              <div class="metric"><b>${analytics.downloads || 0}</b><span>Downloads</span></div>
            </div>

            <div class="panel">
              <h3>Add Book</h3>
              <form class="form-grid" id="addBookForm">
                <input class="control" id="bookTitle" name="title" placeholder="Title" required />
                <input class="control" id="bookAuthor" name="author" placeholder="Author" required />
                <input class="control" id="bookPrice" name="price" type="number" min="0" step="0.01" placeholder="Price in USD, example 9.99" />
                <select class="control" id="bookCategory" name="categoryId">
                  <option value="">No category</option>
                  ${state.categories.map(c => `<option value="${escapeHtml(c.id)}">${escapeHtml(c.name)}</option>`).join('')}
                </select>
                <select class="control" id="bookAccess" name="access">
                  <option value="PAID">Paid download</option>
                  <option value="FREE">Free read-only</option>
                </select>
                <select class="control" id="bookReaderFormat" name="readerFormat">
                  <option value="CHAPTERS">Chapters</option>
                  <option value="TXT">TXT</option>
                  <option value="HTML">HTML</option>
                  <option value="PDF">PDF</option>
                </select>
                <input class="control full" id="coverFile" name="coverFile" type="file" accept="image/*" />
                <input class="control full" id="ebookFile" name="ebookFile" type="file" accept=".pdf,.epub" />
                <textarea class="control textarea full" id="bookDescription" name="description" placeholder="Description" required></textarea>
                <textarea class="control textarea full" id="bookReaderContent" name="readerContent" placeholder="Optional free TXT/HTML reader content"></textarea>
                <label class="pill"><input type="checkbox" id="bookFeatured" name="featured" /> Featured</label>
                <button class="btn primary" type="submit">Save Book</button>
              </form>
              <div id="addBookDebug" class="section-sub" style="margin-top:12px"></div>
            </div>
          </section>
        </div>
      </div>`;
    } catch (err) {
      state.adminToken = '';
      localStorage.removeItem('readora_admin_token');
      $('#view').innerHTML = errorView(err);
    }
  }

  async function loginAdmin(form) {
    const debug = $('#adminLoginDebug');
    const button = $('#adminLoginButton');

    try {
      if (debug) debug.textContent = 'Logging in...';
      if (button) button.disabled = true;

      const email = form.email.value.trim();
      const password = form.password.value;

      const out = await api('/api/admin/login', {
        method: 'POST',
        body: JSON.stringify({ email, password })
      });

      state.adminToken = out.token || 'cookie';
      localStorage.setItem('readora_admin_token', state.adminToken);

      toast('Admin login successful');
      render();
    } catch (err) {
      if (debug) debug.textContent = err.message;
      toast(err.message);
    } finally {
      if (button) button.disabled = false;
    }
  }

  function logoutAdmin() {
    state.adminToken = '';
    localStorage.removeItem('readora_admin_token');
    api('/api/admin/logout', { method: 'POST' }).catch(() => {});
    render();
  }

  async function createBook(form) {
    const debug = $('#addBookDebug');

    try {
      if (debug) debug.textContent = 'Uploading files...';

      const coverFile = form.coverFile.files && form.coverFile.files[0] ? form.coverFile.files[0] : null;
      const ebookFile = form.ebookFile.files && form.ebookFile.files[0] ? form.ebookFile.files[0] : null;

      const coverKey = coverFile ? await uploadAdminFile(coverFile, 'cover') : null;
      const ebookKey = ebookFile ? await uploadAdminFile(ebookFile, 'ebook') : null;

      if (debug) debug.textContent = 'Saving book...';

      const title = form.title.value.trim();
      const access = form.access.value;
      const price = access === 'FREE' ? 0 : Math.round(Number(form.price.value || 0) * 100);
      const ebookName = ebookFile ? ebookFile.name.toLowerCase() : '';

      const body = {
        title,
        slug: slugify(title),
        author: form.author.value.trim(),
        categoryId: form.categoryId.value || null,
        description: form.description.value.trim(),
        previewText: form.description.value.trim().slice(0, 500),
        access,
        priceCents: price,
        coverKey,
        epubKey: ebookKey && ebookName.endsWith('.epub') ? ebookKey : null,
        pdfKey: ebookKey && ebookName.endsWith('.pdf') ? ebookKey : null,
        readerFormat: form.readerFormat.value,
        readerContent: form.readerContent.value.trim() || null,
        allowFreeDownload: false,
        featured: Boolean(form.featured.checked)
      };

      await api('/api/admin/books', {
        method: 'POST',
        body: JSON.stringify(body)
      });

      if (debug) debug.textContent = 'Book created.';
      toast('Book created');
      location.hash = '#browse';
    } catch (err) {
      if (debug) debug.textContent = err.message;
      toast(err.message);
    }
  }

  function renderSimplePage(name) {
    const key = name.toLowerCase();
    const pages = {
      about: ['About Readora', 'Readora is a premium digital bookstore for discovering ebooks, reading selected free titles online, and buying paid ebooks with secure crypto checkout.'],
      contact: ['Contact', 'For support, purchase help, author submissions, refunds for failed downloads, or security reports, contact support@readora.example. Replace this with your real support email.'],
      privacy: ['Privacy Policy', 'Readora collects only what is needed for purchases, download security, admin audit logs, and reader progress. We do not sell personal data.'],
      terms: ['Terms of Service', 'Free books are provided for online reading unless download is explicitly enabled. Paid ebook download links are one-time only and expire after first redemption or after 24 hours.']
    };

    const p = pages[key] || [name, 'Readora page'];

    $('#view').innerHTML = `<div class="page browse-shell">
      <div class="eyebrow">Readora</div>
      <h1 class="page-title">${escapeHtml(p[0])}</h1>
      <p class="lead">${escapeHtml(p[1])}</p>
    </div>`;
  }

  function parseRoute() {
    if (location.hash) {
      const h = location.hash.replace(/^#/, '') || 'home';
      const [path, qs = ''] = h.split('?');
      return { path, params: Object.fromEntries(new URLSearchParams(qs)) };
    }

    const clean = location.pathname.replace(/^\/+/, '').replace(/\/+$/, '');
    if (!clean) return { path: 'home', params: {} };
    if (clean === 'login') return { path: 'admin', params: {} };
    return { path: clean, params: {} };
  }

  function render() {
    setWish();

    const { path, params } = parseRoute();
    const [route, id] = path.split('/');

    $$('.nav a').forEach(a => a.classList.toggle('active', a.dataset.route === route));

    if (route === 'home') return renderHome();
    if (route === 'browse') return renderBrowse(params);
    if (route === 'details') return renderDetails(id);
    if (route === 'reader') return renderReader(id);
    if (route === 'checkout') return renderCheckout(id);
    if (route === 'wishlist') return renderWishlist();
    if (route === 'admin') return renderAdmin();

    return renderSimplePage(route.charAt(0).toUpperCase() + route.slice(1).replace(/-/g, ' '));
  }

  document.addEventListener('click', function (event) {
    const target = event.target.closest('[data-action]');
    if (!target) return;

    const action = target.dataset.action;

    if (action === 'wishlist') {
      event.preventDefault();
      event.stopPropagation();
      toggleWish(target.dataset.slug);
      return;
    }

    if (action === 'details') {
      event.preventDefault();
      location.hash = '#details/' + target.dataset.slug;
      return;
    }

    if (action === 'start-checkout') {
      event.preventDefault();
      startCheckout(target.dataset.bookId);
      return;
    }

    if (action === 'poll-payment') {
      event.preventDefault();
      if (state.pendingPurchase) pollPaymentStatus(state.pendingPurchase);
      return;
    }

    if (action === 'redeem-download') {
      event.preventDefault();
      redeemDownload(target.dataset.token);
      return;
    }

    if (action === 'logout-admin') {
      event.preventDefault();
      logoutAdmin();
      return;
    }
  });

  document.addEventListener('submit', function (event) {
    const form = event.target;

    if (form.id === 'globalSearch') {
      event.preventDefault();
      const q = $('#searchInput').value.trim();
      location.hash = '#browse' + (q ? '?q=' + encodeURIComponent(q) : '');
      return;
    }

    if (form.id === 'browseForm') {
      event.preventDefault();

      const fd = new FormData(form);
      const qs = new URLSearchParams();

      const q = String(fd.get('q') || '').trim();
      const category = String(fd.get('category') || 'all');
      const access = String(fd.get('access') || 'all');
      const sort = String(fd.get('sort') || 'popularity');

      if (q) qs.set('q', q);
      if (category !== 'all') qs.set('category', category);
      if (access !== 'all') qs.set('access', access);
      if (sort) qs.set('sort', sort);

      location.hash = '#browse' + (qs.toString() ? '?' + qs.toString() : '');
      return;
    }

    if (form.id === 'adminLoginForm') {
      event.preventDefault();
      loginAdmin(form);
      return;
    }

    if (form.id === 'addBookForm') {
      event.preventDefault();
      createBook(form);
      return;
    }
  });

  document.addEventListener('DOMContentLoaded', function () {
    const menuBtn = $('#menuBtn');
    const mobileNav = $('#mobileNav');

    if (menuBtn && mobileNav) {
      menuBtn.addEventListener('click', () => mobileNav.classList.toggle('open'));
      mobileNav.addEventListener('click', () => mobileNav.classList.remove('open'));
    }

    render();
  });

  window.addEventListener('hashchange', render);

  window.ReadoraDebug = {
    state,
    api,
    render,
    uploadAdminFile,
    pollPaymentStatus,
    redeemDownload
  };
})();
</script>
</body>
</html>
'@

$IndexHtml = $IndexTemplate.Replace("__STYLE_BLOCK__", $StyleBlock)
Set-Content -Path (Join-Path $PublicDir "index.html") -Value $IndexHtml -Encoding UTF8
Set-Content -Path (Join-Path $ProjectRoot "preview.html") -Value $IndexHtml -Encoding UTF8

$CopyPublic = @'
const fs = require('fs');
const path = require('path');

const root = process.cwd();
const from = path.join(root, 'public');
const to = path.join(root, 'dist', 'public');

function copyDir(src, dest) {
  if (!fs.existsSync(src)) {
    console.log('No public directory found, skipping copy.');
    return;
  }

  fs.mkdirSync(dest, { recursive: true });

  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

copyDir(from, to);
console.log(`Copied ${from} -> ${to}`);
'@
Set-Content -Path (Join-Path $ScriptsDir "copy-public.cjs") -Value $CopyPublic -Encoding UTF8

$PackagePath = Join-Path $ProjectRoot "package.json"
$Package = Get-Content $PackagePath -Raw | ConvertFrom-Json

if (-not $Package.dependencies) {
  $Package | Add-Member -MemberType NoteProperty -Name dependencies -Value ([pscustomobject]@{})
}
if (-not $Package.devDependencies) {
  $Package | Add-Member -MemberType NoteProperty -Name devDependencies -Value ([pscustomobject]@{})
}
if (-not $Package.scripts) {
  $Package | Add-Member -MemberType NoteProperty -Name scripts -Value ([pscustomobject]@{})
}

$Package.dependencies | Add-Member -Force -MemberType NoteProperty -Name "multer" -Value "latest"
$Package.devDependencies | Add-Member -Force -MemberType NoteProperty -Name "@types/multer" -Value "latest"

$Package.scripts.build = "tsc -p tsconfig.json && node scripts/copy-public.cjs"
$Package.scripts.start = "node dist/server.js"

Set-Content -Path $PackagePath -Value (($Package | ConvertTo-Json -Depth 30) + "`n") -Encoding UTF8

$EnvNotePath = Join-Path $ProjectRoot ".env.nowpayments.backblaze.example"
$EnvNote = @'
BTCPAY_MODE=nowpayments
NOWPAYMENTS_API_KEY=paste_your_nowpayments_api_key_here
NOWPAYMENTS_IPN_SECRET=paste_your_nowpayments_ipn_secret_here

STORAGE_DRIVER=s3
R2_ENDPOINT=https://s3.us-east-005.backblazeb2.com
R2_ACCESS_KEY_ID=paste_backblaze_key_id
R2_SECRET_ACCESS_KEY=paste_backblaze_application_key
R2_BUCKET=readora-ebooks
R2_REGION=us-east-005

NOWPayments IPN URL:
https://readora-production-b73c.up.railway.app/api/webhooks/nowpayments
'@
Set-Content -Path $EnvNotePath -Value $EnvNote -Encoding UTF8

try {
  npm install
  npm run build
} catch {
  Write-Host "Local build failed. Continuing to git commit/push. Error:"
  Write-Host $_
}

git add .

$Status = git status --porcelain

if ($Status) {
  git commit -m "Add Backblaze uploads and NOWPayments checkout"
} else {
  Write-Host "No changes to commit."
}

git push origin HEAD:main
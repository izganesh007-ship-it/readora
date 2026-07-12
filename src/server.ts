import express from 'express';
import cookieParser from 'cookie-parser';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { env } from './config/env.js';
import { apiLimiter, corsMiddleware, helmetMiddleware } from './middleware/security.js';
import { booksRouter } from './routes/books.js';
import { categoriesRouter } from './routes/categories.js';
import { checkoutRouter } from './routes/checkout.js';
import { webhooksRouter } from './routes/webhooks.js';
import { downloadsRouter } from './routes/downloads.js';
import { adminRouter } from './routes/admin.js';
import { homeRouter } from './routes/home.js';
import { readerRouter } from './routes/reader.js';
import { purchasesRouter } from './routes/purchases.js';
import { uploadsRouter } from './routes/uploads.js';
import { filesRouter } from './routes/files.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();

app.set('trust proxy', 1);
app.use(helmetMiddleware);
app.use(corsMiddleware);
app.use(cookieParser(env.COOKIE_SECRET));

// Keep raw body for BTCPay HMAC verification.
app.use('/api/webhooks/btcpay', express.json({ verify: (req: any, _res, buf) => { req.rawBody = Buffer.from(buf); } }));
app.use(express.json({ limit: '1mb' }));
app.use(apiLimiter);

app.get('/health', (_req, res) => res.json({ ok: true, service: 'readora-api' }));
app.use('/api/home', homeRouter);
app.use('/api/books', booksRouter);
app.use('/api/categories', categoriesRouter);
app.use('/api/checkout', checkoutRouter);
app.use('/api/webhooks', webhooksRouter);
app.use('/api/downloads', downloadsRouter);
app.use('/api/reader', readerRouter);
app.use('/api/purchases', purchasesRouter);
app.use('/api/admin', adminRouter);
app.use('/api/admin/uploads', uploadsRouter);
app.use('/api/files', filesRouter);

// Serve the standalone preview in development/demo deployments.
app.get('/', (_req, res) => res.sendFile(path.resolve(__dirname, '../preview.html')));

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err);
  const status = err.status || err.statusCode || 500;
  res.status(status).json({ error: status === 500 ? 'Internal server error' : err.message, details: env.NODE_ENV === 'development' ? err.stack : undefined });
});

app.listen(env.PORT, () => console.log(`Readora API listening on ${env.PORT}`));

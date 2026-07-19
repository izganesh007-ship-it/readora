import express from 'express';
import cookieParser from 'cookie-parser';
import path from 'node:path';
import fs from 'node:fs';
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

const distPublicDir = path.resolve(__dirname, 'public');
const rootPublicDir = path.resolve(__dirname, '../public');
const publicDir = fs.existsSync(distPublicDir) ? distPublicDir : rootPublicDir;
const indexHtml = path.join(publicDir, 'index.html');

app.set('trust proxy', 1);
app.use(helmetMiddleware);
app.use(corsMiddleware);
app.use(cookieParser(env.COOKIE_SECRET));

app.use('/api/webhooks/btcpay', express.json({
  verify: (req: any, _res, buf) => {
    req.rawBody = Buffer.from(buf);
  }
}));

app.use(express.json({ limit: '5mb' }));
app.use(apiLimiter);

app.use(express.static(publicDir, {
  index: false,
  extensions: ['html'],
  maxAge: env.NODE_ENV === 'production' ? '1h' : 0
}));

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'readora-api' });
});

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

app.get('/', (_req, res) => {
  res.sendFile(indexHtml);
});

app.get(/.*/, (req, res, next) => {
  if (req.path.startsWith('/api/')) return next();
  res.sendFile(indexHtml);
});

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  // Multer errors (file too large, too many files, etc.)
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'File too large' });
  }
  if (err.code === 'LIMIT_UNEXPECTED_FILE' || err.code === 'LIMIT_FILE_COUNT') {
    return res.status(400).json({ error: err.message || 'Upload error' });
  }
  // Zod validation errors
  if (err.name === 'ZodError' && err.issues) {
    const message = err.issues.map((i: any) => `${i.path.join('.')}: ${i.message}`).join('; ');
    return res.status(400).json({ error: message });
  }
  // Errors with an explicit status
  const status = err.status || err.statusCode || 500;
  console.error(err);
  res.status(status).json({
    error: status === 500 ? 'Internal server error' : err.message,
    details: env.NODE_ENV === 'development' ? err.stack : undefined
  });
});

app.listen(env.PORT, () => {
  console.log(`Readora API listening on ${env.PORT}`);
  console.log(`Readora frontend served from ${publicDir}`);
});

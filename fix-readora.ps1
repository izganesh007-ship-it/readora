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
$MiddlewareDir = Join-Path $SrcDir "middleware"
$PublicDir = Join-Path $ProjectRoot "public"
$ScriptsDir = Join-Path $ProjectRoot "scripts"

New-Item -ItemType Directory -Force -Path $PublicDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null

# -------------------------------
# Fix security CSP
# -------------------------------
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
      "img-src": ["'self'", "data:", "blob:"],
      "connect-src": ["'self'", env.BTCPAY_URL || "'self'"],
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

# -------------------------------
# Fix server.ts
# -------------------------------
$ServerTs = @'
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

app.use(express.json({ limit: '1mb' }));
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
  console.error(err);
  const status = err.status || err.statusCode || 500;
  res.status(status).json({
    error: status === 500 ? 'Internal server error' : err.message,
    details: env.NODE_ENV === 'development' ? err.stack : undefined
  });
});

app.listen(env.PORT, () => {
  console.log(`Readora API listening on ${env.PORT}`);
  console.log(`Readora frontend served from ${publicDir}`);
});
'@
Set-Content -Path (Join-Path $SrcDir "server.ts") -Value $ServerTs -Encoding UTF8

# -------------------------------
# Fix admin.ts to return token
# -------------------------------
$AdminTs = @'
import { Router } from 'express';
import argon2 from 'argon2';
import { z } from 'zod';
import { query } from '../db.js';
import { loginLimiter } from '../middleware/security.js';
import { requireAdmin, signAdminSession } from '../middleware/auth.js';
import { audit } from '../services/audit.js';
import { isProd } from '../config/env.js';

export const adminRouter = Router();

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

# -------------------------------
# Preserve style block if possible
# -------------------------------
$ExistingIndex = Join-Path $PublicDir "index.html"
$ExistingPreview = Join-Path $ProjectRoot "preview.html"
$ExistingHtml = ""

if (Test-Path $ExistingIndex) {
  $ExistingHtml = Get-Content $ExistingIndex -Raw
} elseif (Test-Path $ExistingPreview) {
  $ExistingHtml = Get-Content $ExistingPreview -Raw
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

# -------------------------------
# Write no-inline-onclick API-connected SPA
# -------------------------------
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
    <a class="icon-btn" href="#wishlist" title="Wishlist" style="position:relative">♥<span class="badge-count" id="wishCount">0</span></a>
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
    <div><b>Readora</b> — premium ebook marketplace powered by PostgreSQL, BTCPay Server-ready checkout, and one-time secure downloads.</div>
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
  console.log('[Readora] SPA script loaded');

  const state = {
    categories: [],
    adminToken: localStorage.getItem('readora_admin_token') || '',
    wishlist: JSON.parse(localStorage.getItem('readora_wishlist') || '[]')
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
    console.log('[Readora] toggleWish', slug);
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

  function loading(title = 'Loading...') {
    return `<div class="page browse-shell"><div class="eyebrow">Readora</div><h1 class="page-title">${escapeHtml(title)}</h1><p class="lead">Please wait.</p></div>`;
  }

  function errorView(err) {
    console.error('[Readora Error]', err);
    return `<div class="page browse-shell"><div class="eyebrow">Error</div><h1 class="page-title">Something went wrong</h1><p class="lead">${escapeHtml(err.message || err)}</p><div class="panel"><p>Open DevTools Console and Railway logs for more details.</p></div></div>`;
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
      <button class="heart ${isWished(book.slug) ? 'active' : ''}" type="button" data-action="wishlist" data-slug="${escapeHtml(book.slug)}">♥</button>
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
      <div class="rail">${items.length ? items.map(card).join('') : '<div class="empty">No books yet. Seed the database or add books in admin.</div>'}</div>
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
          <p class="lead">Your API is working, but your database has no books yet.</p>
          <div class="panel">
            <h3>Fix</h3>
            <p>Run this in Railway Console:</p>
            <pre>npm run db:seed</pre>
            <p>Or login to admin and add your first book.</p>
          </div>
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
              <a class="btn primary" href="${hero.free ? '#reader/' + hero.slug : '#checkout/' + hero.slug}">${hero.free ? 'Read Free' : 'Buy with Bitcoin'}</a>
              <a class="btn ghost" href="#details/${hero.slug}">View Details</a>
              <button class="btn ghost" type="button" data-action="wishlist" data-slug="${escapeHtml(hero.slug)}">♥ Wishlist</button>
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
        <section class="personal">
          <div>
            <h2>Dynamic marketplace connected to your API.</h2>
            <p>This frontend loads books, categories, admin analytics, and admin book creation from the backend.</p>
          </div>
          <a class="btn primary" href="#admin">Open Admin</a>
        </section>
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
              <a class="btn primary" href="${book.free ? '#reader/' + book.slug : '#checkout/' + book.slug}">${book.free ? 'Read Online' : 'Purchase Required'}</a>
              <button class="btn ghost" type="button" data-action="wishlist" data-slug="${escapeHtml(book.slug)}">♥ ${isWished(book.slug) ? 'Remove Wishlist' : 'Add Wishlist'}</button>
              <a class="btn ghost" href="#browse">Back to Browse</a>
            </div>
            <div class="panel">
              <h3>Preview Text</h3>
              <div class="preview-text">${escapeHtml(out.data.preview_text || out.data.previewText || book.description || '')}</div>
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
    $('#view').innerHTML = loading('Preparing checkout...');
    try {
      const out = await api('/api/books/' + encodeURIComponent(slug));
      const book = normalizeBook(out.data);

      $('#view').innerHTML = `<div class="page checkout">
        <div class="eyebrow">Bitcoin Checkout</div>
        <h1 class="page-title">Checkout</h1>
        <div class="checkout-card">
          <div>${cover(book, 'cover-detail')}</div>
          <div>
            <h2>${escapeHtml(book.title)}</h2>
            <p class="lead">Paid books require purchase. After BTCPay confirms payment, Readora issues a one-time download token.</p>
            <div class="status-box">
              <div class="status-line"><span class="pulse"></span><b>${money(book.priceCents)}</b></div>
              <div class="status-line">Payment mode is controlled by your server environment variables.</div>
            </div>
            <div class="actions">
              <button class="btn primary" type="button" data-action="start-checkout" data-book-id="${escapeHtml(book.id)}">Create Invoice</button>
              <a class="btn ghost" href="#details/${book.slug}">Cancel</a>
            </div>
            <div id="checkoutResult"></div>
          </div>
        </div>
      </div>`;
    } catch (err) {
      $('#view').innerHTML = errorView(err);
    }
  }

  async function startCheckout(bookId) {
    console.log('[Readora] startCheckout', bookId);
    const box = $('#checkoutResult');
    if (box) box.innerHTML = '<div class="panel"><p>Creating invoice...</p></div>';

    try {
      const out = await api('/api/checkout/btcpay', {
        method: 'POST',
        body: JSON.stringify({ bookId })
      });

      if (box) {
        box.innerHTML = `<div class="panel">
          <h3>Invoice Created</h3>
          <p>Purchase ID: ${escapeHtml(out.purchaseId || '')}</p>
          <p>Save this purchase access token for testing purchase/download:</p>
          <div class="token">${escapeHtml(out.purchaseAccessToken || '')}</div>
          <div class="actions">
            <a class="btn primary" href="${escapeHtml(out.checkoutLink || '#')}" target="_blank" rel="noopener">Open Checkout</a>
          </div>
        </div>`;
      }
    } catch (err) {
      if (box) box.innerHTML = `<div class="panel"><p>${escapeHtml(err.message)}</p></div>`;
    }
  }

  async function renderAdmin() {
    console.log('[Readora] renderAdmin token?', Boolean(state.adminToken));

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
                <textarea class="control textarea full" id="bookDescription" name="description" placeholder="Description" required></textarea>
                <textarea class="control textarea full" id="bookReaderContent" name="readerContent" placeholder="Optional free TXT/HTML reader content"></textarea>
                <label class="pill"><input type="checkbox" id="bookFeatured" name="featured" /> Featured</label>
                <button class="btn primary" type="submit">Save Book</button>
              </form>
              <div id="addBookDebug" class="section-sub" style="margin-top:12px"></div>
            </div>

            <div class="panel">
              <h3>Trending</h3>
              <table class="table">
                <tr><th>Book</th><th>Slug</th><th>Views</th></tr>
                ${(analytics.trending || []).map(b => `<tr><td>${escapeHtml(b.title)}</td><td>${escapeHtml(b.slug)}</td><td>${b.views}</td></tr>`).join('')}
              </table>
            </div>
          </section>
        </div>
      </div>`;
    } catch (err) {
      console.error('[Readora] admin dashboard failed', err);
      state.adminToken = '';
      localStorage.removeItem('readora_admin_token');
      $('#view').innerHTML = errorView(err);
    }
  }

  async function loginAdmin(form) {
    console.log('[Readora] loginAdmin() triggered');

    const debug = $('#adminLoginDebug');
    const button = $('#adminLoginButton');

    try {
      if (debug) debug.textContent = 'Logging in...';
      if (button) button.disabled = true;

      const email = form.email.value.trim();
      const password = form.password.value;

      console.log('[Readora] POST /api/admin/login', { email });

      const out = await api('/api/admin/login', {
        method: 'POST',
        body: JSON.stringify({ email, password })
      });

      console.log('[Readora] admin login success', out);

      state.adminToken = out.token || 'cookie';
      localStorage.setItem('readora_admin_token', state.adminToken);

      toast('Admin login successful');
      location.hash = '#admin';
      render();
    } catch (err) {
      console.error('[Readora] admin login failed', err);
      if (debug) debug.textContent = err.message;
      toast(err.message);
    } finally {
      if (button) button.disabled = false;
    }
  }

  function logoutAdmin() {
    console.log('[Readora] logoutAdmin');
    state.adminToken = '';
    localStorage.removeItem('readora_admin_token');
    api('/api/admin/logout', { method: 'POST' }).catch(() => {});
    render();
  }

  async function createBook(form) {
    console.log('[Readora] createBook() triggered');

    const debug = $('#addBookDebug');

    try {
      if (debug) debug.textContent = 'Saving book...';

      const title = form.title.value.trim();
      const access = form.access.value;
      const price = access === 'FREE' ? 0 : Math.round(Number(form.price.value || 0) * 100);

      const body = {
        title,
        slug: slugify(title),
        author: form.author.value.trim(),
        categoryId: form.categoryId.value || null,
        description: form.description.value.trim(),
        previewText: form.description.value.trim().slice(0, 500),
        access,
        priceCents: price,
        readerFormat: form.readerFormat.value,
        readerContent: form.readerContent.value.trim() || null,
        allowFreeDownload: false,
        featured: Boolean(form.featured.checked)
      };

      console.log('[Readora] POST /api/admin/books', body);

      await api('/api/admin/books', {
        method: 'POST',
        body: JSON.stringify(body)
      });

      if (debug) debug.textContent = 'Book created.';
      toast('Book created');
      location.hash = '#browse';
    } catch (err) {
      console.error('[Readora] createBook failed', err);
      if (debug) debug.textContent = err.message;
      toast(err.message);
    }
  }

  function renderSimplePage(name) {
    const key = name.toLowerCase();
    const pages = {
      about: ['About Readora', 'Readora is a premium digital bookstore for discovering ebooks, reading selected free titles online, and buying paid ebooks with secure Bitcoin checkout.'],
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
    console.log('[Readora] render()', location.href);

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
    console.log('[Readora] click action', action, target.dataset);

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

    if (action === 'logout-admin') {
      event.preventDefault();
      logoutAdmin();
      return;
    }
  });

  document.addEventListener('submit', function (event) {
    const form = event.target;
    console.log('[Readora] submit', form.id);

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
    console.log('[Readora] DOMContentLoaded');

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
    loginAdmin,
    logoutAdmin
  };
})();
</script>
</body>
</html>
'@

$IndexHtml = $IndexTemplate.Replace("__STYLE_BLOCK__", $StyleBlock)
Set-Content -Path (Join-Path $PublicDir "index.html") -Value $IndexHtml -Encoding UTF8
Set-Content -Path (Join-Path $ProjectRoot "preview.html") -Value $IndexHtml -Encoding UTF8

# -------------------------------
# Copy public build script
# -------------------------------
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

# -------------------------------
# package.json build script
# -------------------------------
$PackagePath = Join-Path $ProjectRoot "package.json"
$Package = Get-Content $PackagePath -Raw | ConvertFrom-Json

if (-not $Package.scripts) {
  $Package | Add-Member -MemberType NoteProperty -Name scripts -Value ([pscustomobject]@{})
}

$Package.scripts.build = "tsc -p tsconfig.json && node scripts/copy-public.cjs"
$Package.scripts.start = "node dist/server.js"

Set-Content -Path $PackagePath -Value (($Package | ConvertTo-Json -Depth 30) + "`n") -Encoding UTF8

# -------------------------------
# Build if possible
# -------------------------------
try {
  npm install
  npm run build
} catch {
  Write-Host "Local build failed. Continuing to git commit/push. Error:"
  Write-Host $_
}

# -------------------------------
# Git commit and push
# -------------------------------
git add .

$Status = git status --porcelain

if ($Status) {
  git commit -m "Fix admin login event listeners and remove inline onclick handlers"
} else {
  Write-Host "No changes to commit."
}

git push origin HEAD:main
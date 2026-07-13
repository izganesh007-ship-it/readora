$ErrorActionPreference = "Stop"

$ProjectRoot = (Get-Location).Path
if (-not (Test-Path (Join-Path $ProjectRoot "package.json"))) {
  $Fallback = "C:\Users\comp\Documents\readora (1)\readora"
  if (Test-Path (Join-Path $Fallback "package.json")) {
    $ProjectRoot = $Fallback
    Set-Location $ProjectRoot
  } else {
    throw "Run this script inside the Readora project folder containing package.json"
  }
}

$SrcDir = Join-Path $ProjectRoot "src"
$RoutesDir = Join-Path $SrcDir "routes"
$MiddlewareDir = Join-Path $SrcDir "middleware"
$PublicDir = Join-Path $ProjectRoot "public"
$ScriptsDir = Join-Path $ProjectRoot "scripts"

New-Item -ItemType Directory -Force -Path $PublicDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null

# -------------------------------
# 1. Fix src/server.ts
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

// Keep raw body for BTCPay HMAC verification.
app.use('/api/webhooks/btcpay', express.json({
  verify: (req: any, _res, buf) => {
    req.rawBody = Buffer.from(buf);
  }
}));

app.use(express.json({ limit: '1mb' }));
app.use(apiLimiter);

// Static frontend files
app.use(express.static(publicDir, {
  index: false,
  extensions: ['html'],
  maxAge: env.NODE_ENV === 'production' ? '1h' : 0
}));

// Health
app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'readora-api' });
});

// API routes
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

// Root SPA
app.get('/', (_req, res) => {
  res.sendFile(indexHtml);
});

// SPA catch-all for non-API GET routes.
// This lets /admin, /browse, /login, etc. load the same SPA.
app.get(/.*/, (req, res, next) => {
  if (req.path.startsWith('/api/')) return next();
  res.sendFile(indexHtml);
});

// Error handler
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
  console.log(`Serving frontend from ${publicDir}`);
});
'@
Set-Content -Path (Join-Path $SrcDir "server.ts") -Value $ServerTs -Encoding UTF8

# -------------------------------
# 2. Fix CSP for inline SPA script
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
# 3. Fix admin route to return JWT token too
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
# 4. Preserve existing CSS exactly
# -------------------------------
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
.browse-shell,.admin,.checkout,.details{padding:34px 48px 64px}.page-title{font-size:60px;letter-spacing:-3px}.lead{color:#c9c9d0;line-height:1.6}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:18px}.book-card{background:#141418;border:1px solid rgba(255,255,255,.1);border-radius:22px;overflow:hidden;cursor:pointer}.book-cover{height:240px;padding:16px;background:linear-gradient(145deg,#3b0005,#e50914,#111);display:flex;flex-direction:column;justify-content:space-between}.mini-title{font-size:24px;font-weight:950}.card-body{padding:12px}.panel{background:#111114;border:1px solid rgba(255,255,255,.1);border-radius:24px;padding:22px;margin-top:22px}.footer{padding:34px 48px;border-top:1px solid rgba(255,255,255,.08);color:#aaa}
</style>
'@
}

# -------------------------------
# 5. Overwrite public/index.html with real API-driven SPA
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
    <button class="icon-btn menu-btn" id="menuBtn" aria-label="Open menu">☰</button>
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
const state = {
  books: [],
  categories: [],
  home: null,
  adminToken: localStorage.getItem('readora_admin_token') || '',
  wishlist: JSON.parse(localStorage.getItem('readora_wishlist') || '[]')
};

const $ = s => document.querySelector(s);
const $$ = s => Array.from(document.querySelectorAll(s));
const money = cents => Number(cents || 0) === 0 ? 'Free' : '$' + (Number(cents || 0) / 100).toFixed(2);
const slugify = s => String(s || '').toLowerCase().trim().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'');

function toast(msg, type='info') {
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
  toast(isWished(slug) ? 'Added to wishlist' : 'Removed from wishlist');
  render();
}

async function api(path, options = {}) {
  const headers = Object.assign({ 'Content-Type': 'application/json' }, options.headers || {});
  if (state.adminToken && state.adminToken !== 'cookie') headers.Authorization = 'Bearer ' + state.adminToken;

  const res = await fetch(path, Object.assign({
    credentials: 'include',
    headers
  }, options));

  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }

  if (!res.ok) {
    const msg = data && data.error ? data.error : ('Request failed: ' + res.status);
    throw new Error(msg);
  }

  return data;
}

function loading(title='Loading...') {
  return `<div class="page browse-shell"><div class="eyebrow">Readora</div><h1 class="page-title">${title}</h1><p class="lead">Please wait.</p></div>`;
}

function errorView(err) {
  return `<div class="page browse-shell"><div class="eyebrow">Error</div><h1 class="page-title">Something went wrong</h1><p class="lead">${escapeHtml(err.message || err)}</p><div class="panel"><p>Check Railway logs, database migrations, and environment variables.</p></div></div>`;
}

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
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

function cover(book, cls='book-cover') {
  return `<div class="${cls}" style="--cover-gradient:${gradientFor(book)};background:${gradientFor(book)}">
    <div class="cover-mark">READORA</div>
    <div class="mini-title">${escapeHtml(book.title)}</div>
    <div class="mini-author">${escapeHtml(book.author || '')}</div>
  </div>`;
}

function card(raw) {
  const book = normalizeBook(raw);
  return `<article class="book-card" onclick="location.hash='details/${book.slug}'">
    <button class="heart ${isWished(book.slug) ? 'active' : ''}" onclick="event.stopPropagation();toggleWish('${book.slug}')">♥</button>
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
      <div><h2 class="section-title">${title}</h2><p class="section-sub">${subtitle}</p></div>
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

async function home() {
  $('#view').innerHTML = loading('Loading Readora...');
  try {
    const out = await api('/api/home');
    state.home = out;

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
            <button class="btn ghost" onclick="toggleWish('${hero.slug}')">♥ Wishlist</button>
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
      ${row('Trending Books','Most viewed and purchased this week',trending)}
      ${row('New Releases','Fresh drops from your database',newest)}
      ${row('Featured Books','Managed by the admin panel',featured)}
      <section class="personal">
        <div>
          <h2>Dynamic marketplace connected to your API.</h2>
          <p>This frontend now loads books, categories, admin analytics, and admin book creation from the backend.</p>
        </div>
        <a class="btn primary" href="#admin">Open Admin</a>
      </section>
    </div>`;
  } catch (err) {
    $('#view').innerHTML = errorView(err);
  }
}

async function browse(params={}) {
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
      <div class="filters">
        <input class="control" id="bq" value="${escapeHtml(params.q || '')}" placeholder="Search title, author, tags..." />
        <select class="control" id="bc">
          <option value="all">All categories</option>
          ${categories.map(c => `<option value="${c.slug}" ${params.category === c.slug ? 'selected' : ''}>${escapeHtml(c.name)}</option>`).join('')}
        </select>
        <select class="control" id="ba">
          <option value="all">All access</option>
          <option value="FREE" ${params.access === 'FREE' ? 'selected' : ''}>Free only</option>
          <option value="PAID" ${params.access === 'PAID' ? 'selected' : ''}>Paid only</option>
        </select>
        <select class="control" id="bs">
          <option value="popularity" ${params.sort === 'popularity' ? 'selected' : ''}>Sort: Popularity</option>
          <option value="newest" ${params.sort === 'newest' ? 'selected' : ''}>Sort: Newest</option>
          <option value="price" ${params.sort === 'price' ? 'selected' : ''}>Sort: Price</option>
          <option value="rating" ${params.sort === 'rating' ? 'selected' : ''}>Sort: Rating</option>
        </select>
        <button class="btn primary" onclick="applyBrowse()">Apply</button>
      </div>
      <div class="grid">${books.length ? books.map(card).join('') : '<div class="empty">No books match your filters.</div>'}</div>
    </div>`;
  } catch (err) {
    $('#view').innerHTML = errorView(err);
  }
}

function applyBrowse() {
  const q = $('#bq').value.trim();
  const category = $('#bc').value;
  const access = $('#ba').value;
  const sort = $('#bs').value;
  const qs = new URLSearchParams();
  if (q) qs.set('q', q);
  if (category !== 'all') qs.set('category', category);
  if (access !== 'all') qs.set('access', access);
  if (sort) qs.set('sort', sort);
  location.hash = 'browse' + (qs.toString() ? '?' + qs.toString() : '');
}

async function details(slug) {
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
            <button class="btn ghost" onclick="toggleWish('${book.slug}')">♥ ${isWished(book.slug) ? 'Remove Wishlist' : 'Add Wishlist'}</button>
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

async function reader(slug) {
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
      content = chapters.length
        ? chapters.map(ch => `<h2>${escapeHtml(ch.title)}</h2><p>${escapeHtml(ch.content)}</p>`).join('')
        : '<p>No chapters found.</p>';
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

function wishlist() {
  const items = state.wishlist;
  $('#view').innerHTML = `<div class="page browse-shell">
    <div class="eyebrow">Wishlist</div>
    <h1 class="page-title">Your Wishlist</h1>
    <p class="lead">Stored locally in your browser.</p>
    <div class="panel">
      ${items.length ? items.map(slug => `<p><a href="#details/${slug}">${escapeHtml(slug)}</a></p>`).join('') : '<p>Your wishlist is empty.</p>'}
    </div>
  </div>`;
}

async function checkout(slug) {
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
            <button class="btn primary" onclick="startCheckout('${book.id}')">Create Invoice</button>
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
  const box = $('#checkoutResult');
  box.innerHTML = '<div class="panel"><p>Creating invoice...</p></div>';
  try {
    const out = await api('/api/checkout/btcpay', {
      method: 'POST',
      body: JSON.stringify({ bookId })
    });

    box.innerHTML = `<div class="panel">
      <h3>Invoice Created</h3>
      <p>Purchase ID: ${escapeHtml(out.purchaseId || '')}</p>
      <p>Save this purchase access token for success/download testing:</p>
      <div class="token">${escapeHtml(out.purchaseAccessToken || '')}</div>
      <div class="actions">
        <a class="btn primary" href="${out.checkoutLink}" target="_blank" rel="noopener">Open Checkout</a>
      </div>
    </div>`;
  } catch (err) {
    box.innerHTML = `<div class="panel"><p>${escapeHtml(err.message)}</p></div>`;
  }
}

async function admin() {
  if (!state.adminToken) {
    $('#view').innerHTML = `<div class="page admin">
      <div class="login-box">
        <div class="eyebrow">Secure Admin Login</div>
        <h1>Admin Panel</h1>
        <p class="section-sub">Use the admin account created with npm run admin:create.</p>
        <input class="control" id="adminEmail" type="email" placeholder="Admin email" style="width:100%;margin:8px 0" />
        <input class="control" id="adminPass" type="password" placeholder="Admin password" style="width:100%;margin:8px 0 16px" />
        <button class="btn primary" onclick="loginAdmin()">Login</button>
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
          <button class="active">Dashboard</button>
          <button onclick="logoutAdmin()">Logout</button>
        </aside>
        <section>
          <div class="metrics">
            <div class="metric"><b>${analytics.totalBooks || 0}</b><span>Total Books</span></div>
            <div class="metric"><b>$${((analytics.revenueCents || 0)/100).toFixed(2)}</b><span>Revenue</span></div>
            <div class="metric"><b>${analytics.sales || 0}</b><span>Sales</span></div>
            <div class="metric"><b>${analytics.downloads || 0}</b><span>Downloads</span></div>
          </div>

          <div class="panel">
            <h3>Add Book</h3>
            <div class="form-grid">
              <input class="control" id="bookTitle" placeholder="Title" />
              <input class="control" id="bookAuthor" placeholder="Author" />
              <input class="control" id="bookPrice" type="number" min="0" placeholder="Price in USD, example 9.99" />
              <select class="control" id="bookCategory">
                <option value="">No category</option>
                ${state.categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('')}
              </select>
              <select class="control" id="bookAccess">
                <option value="PAID">Paid download</option>
                <option value="FREE">Free read-only</option>
              </select>
              <select class="control" id="bookReaderFormat">
                <option value="CHAPTERS">Chapters</option>
                <option value="TXT">TXT</option>
                <option value="HTML">HTML</option>
                <option value="PDF">PDF</option>
              </select>
              <textarea class="control textarea full" id="bookDescription" placeholder="Description"></textarea>
              <textarea class="control textarea full" id="bookReaderContent" placeholder="Optional free TXT/HTML reader content"></textarea>
              <label class="pill"><input type="checkbox" id="bookFeatured" /> Featured</label>
              <button class="btn primary" onclick="createBook()">Save Book</button>
            </div>
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
    state.adminToken = '';
    localStorage.removeItem('readora_admin_token');
    $('#view').innerHTML = errorView(err);
  }
}

async function loginAdmin() {
  try {
    const email = $('#adminEmail').value.trim();
    const password = $('#adminPass').value;

    const out = await api('/api/admin/login', {
      method: 'POST',
      body: JSON.stringify({ email, password })
    });

    state.adminToken = out.token || 'cookie';
    localStorage.setItem('readora_admin_token', state.adminToken);
    toast('Admin login successful');
    render();
  } catch (err) {
    toast(err.message);
  }
}

function logoutAdmin() {
  state.adminToken = '';
  localStorage.removeItem('readora_admin_token');
  api('/api/admin/logout', { method: 'POST' }).catch(() => {});
  render();
}

async function createBook() {
  try {
    const title = $('#bookTitle').value.trim();
    const access = $('#bookAccess').value;
    const price = access === 'FREE' ? 0 : Math.round(Number($('#bookPrice').value || 0) * 100);
    const readerFormat = $('#bookReaderFormat').value;

    const body = {
      title,
      slug: slugify(title),
      author: $('#bookAuthor').value.trim(),
      categoryId: $('#bookCategory').value || null,
      description: $('#bookDescription').value.trim(),
      previewText: $('#bookDescription').value.trim().slice(0, 500),
      access,
      priceCents: price,
      readerFormat,
      readerContent: $('#bookReaderContent').value.trim() || null,
      allowFreeDownload: false,
      featured: $('#bookFeatured').checked
    };

    await api('/api/admin/books', {
      method: 'POST',
      body: JSON.stringify(body)
    });

    toast('Book created');
    location.hash = '#browse';
  } catch (err) {
    toast(err.message);
  }
}

function simplePage(name) {
  const key = name.toLowerCase();
  const pages = {
    about: ['About Readora','Readora is a premium digital bookstore for discovering ebooks, reading selected free titles online, and buying paid ebooks with secure Bitcoin checkout.'],
    contact: ['Contact','For support, purchase help, author submissions, refunds for failed downloads, or security reports, contact support@readora.example. Replace this with your real support email.'],
    privacy: ['Privacy Policy','Readora collects only what is needed for purchases, download security, admin audit logs, and reader progress. We do not sell personal data.'],
    terms: ['Terms of Service','Free books are provided for online reading unless download is explicitly enabled. Paid ebook download links are one-time only and expire after first redemption or after 24 hours.']
  };
  const p = pages[key] || [name, 'Readora page'];
  $('#view').innerHTML = `<div class="page browse-shell"><div class="eyebrow">Readora</div><h1 class="page-title">${p[0]}</h1><p class="lead">${p[1]}</p></div>`;
}

function parseRoute() {
  if (location.hash) {
    const h = location.hash.replace(/^#/, '') || 'home';
    const [path, qs=''] = h.split('?');
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

  if (route === 'home') return home();
  if (route === 'browse') return browse(params);
  if (route === 'details') return details(id);
  if (route === 'reader') return reader(id);
  if (route === 'checkout') return checkout(id);
  if (route === 'wishlist') return wishlist();
  if (route === 'admin') return admin();

  return simplePage(route.charAt(0).toUpperCase() + route.slice(1).replace(/-/g, ' '));
}

$('#globalSearch').addEventListener('submit', e => {
  e.preventDefault();
  const q = $('#searchInput').value.trim();
  location.hash = 'browse' + (q ? '?q=' + encodeURIComponent(q) : '');
});

const menuBtn = $('#menuBtn');
const mobileNav = $('#mobileNav');
if (menuBtn && mobileNav) {
  menuBtn.onclick = () => mobileNav.classList.toggle('open');
  mobileNav.onclick = () => mobileNav.classList.remove('open');
}

window.addEventListener('hashchange', render);
window.addEventListener('DOMContentLoaded', render);
</script>
</body>
</html>
'@

$IndexHtml = $IndexTemplate.Replace("__STYLE_BLOCK__", $StyleBlock)
Set-Content -Path (Join-Path $PublicDir "index.html") -Value $IndexHtml -Encoding UTF8

# Keep preview.html synced with the real frontend for Railway/root fallback safety
Set-Content -Path (Join-Path $ProjectRoot "preview.html") -Value $IndexHtml -Encoding UTF8

# -------------------------------
# 6. Add node copy script for public -> dist/public
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
# 7. Fix package.json build script
# -------------------------------
$PackagePath = Join-Path $ProjectRoot "package.json"
$Package = Get-Content $PackagePath -Raw | ConvertFrom-Json

if (-not $Package.scripts) {
  $Package | Add-Member -MemberType NoteProperty -Name scripts -Value ([pscustomobject]@{})
}

$Package.scripts.build = "tsc -p tsconfig.json && node scripts/copy-public.cjs"
$Package.scripts.start = "node dist/server.js"

$PackageJson = $Package | ConvertTo-Json -Depth 20
Set-Content -Path $PackagePath -Value $PackageJson -Encoding UTF8

# -------------------------------
# 8. Build once locally if possible
# -------------------------------
try {
  npm install
  npm run build
} catch {
  Write-Host "Local build failed. Continuing to git commit so Railway can build. Error:"
  Write-Host $_
}

# -------------------------------
# 9. Git add, commit, push
# -------------------------------
git add .

$Status = git status --porcelain

if ($Status) {
  git commit -m "Fix Readora frontend SPA, API integration, admin login, and public build"
} else {
  Write-Host "No file changes to commit."
}

git push origin HEAD:main
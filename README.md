# Readora

Readora is a premium Netflix-inspired ebook marketplace built from scratch for:

- dark black/red storefront UI
- free online reading with progress tracking
- paid ebook checkout through BTCPay Server
- secure one-time download tokens
- Cloudflare R2/S3 private ebook storage with signed URLs
- PostgreSQL full-text search and indexed schema
- admin dashboard, analytics, audit logs and security controls

## What is included now

1. `preview.html` — a complete responsive clickable UI prototype you can open immediately.
2. `sql/init.sql` and `prisma/schema.prisma` — optimized PostgreSQL schema with full-text search indexes.
3. `src/` — production backend scaffold using Express REST API patterns, BTCPay webhook verification, secure download tokens, R2 signed URLs, admin authentication and rate limiting.
4. `docker-compose.yml` — local PostgreSQL + API development environment.

## Quick preview

Open `preview.html` in a browser. It includes homepage, Browse, Details, Reader, Wishlist, Checkout, Success, Admin, Contact/About/Privacy/Terms placeholder routes.

Demo admin password in the preview: `readora-admin`.

## Local backend setup

```bash
cp .env.example .env
# edit .env with real secrets
npm install
docker compose up -d postgres
npm run db:migrate
npm run dev
```

API base: `http://localhost:8080/api`.

## Production notes

Before going live:

- use real BTCPay Server URL, store id, API key and webhook secret
- use private Cloudflare R2 bucket with no public object access
- create the first admin, then rotate `ADMIN_INITIAL_PASSWORD`
- deploy behind HTTPS only
- set secure cookies and production CORS origin
- run database migrations using a controlled migration pipeline
- connect a Next.js/React frontend to these REST endpoints or port `preview.html` into Next.js components

## REST API overview

- `GET /api/books` — browse/search/filter/sort books
- `GET /api/books/:slug` — book details
- `GET /api/categories` — dynamic categories
- `POST /api/checkout/btcpay` — create BTCPay invoice for paid book
- `POST /api/webhooks/btcpay` — verify BTCPay webhook and confirm purchase
- `POST /api/downloads/:token/redeem` — atomically redeem one-time token and return short-lived signed URL
- `POST /api/admin/login` — secure admin login
- `GET /api/admin/analytics` — dashboard metrics
- `POST /api/admin/books` — add book metadata and private file keys

## Security architecture

- Argon2id password hashing
- HTTP-only secure cookies / JWT session option
- Helmet CSP and security headers
- CSRF protection for cookie-authenticated admin routes
- strict CORS
- login and API rate limiting
- BTCPay HMAC webhook verification
- one-time download links: hash stored in DB, expire after first successful redemption or 24 hours
- R2/S3 signed URLs with very short TTL
- audit logging for admin and download actions
- PostgreSQL parameterized queries only

## Completed backend modules added

- Dynamic homepage API: `/api/home`
- Free reader API with paid-book block: `/api/reader/:slug`
- Reader progress API: `/api/reader/:slug/progress`
- Purchase status and purchase access token flow: `/api/purchases/:id`
- One-time download-token issuing after payment: `/api/purchases/:id/download-token`
- Atomic token redemption with short-lived R2 signed URL: `/api/downloads/:token/redeem`
- Admin direct-to-R2 signed upload URLs: `/api/admin/uploads/sign`
- Seed data: `sql/seed.sql`
- Admin bootstrap: `npm run admin:create`
- Dockerfile and deployment/security/API docs
- OpenAPI contract: `openapi.yaml`

## Production payment/download flow

```txt
Customer -> POST /api/checkout/btcpay
Readora -> BTCPay invoice
BTCPay -> POST /api/webhooks/btcpay with HMAC
Readora -> marks purchase PAID
Customer success page -> POST /api/purchases/:id/download-token with purchaseAccessToken
Readora -> returns one-time token, stored only as hash
Customer -> POST /api/downloads/:token/redeem
Readora -> transaction locks token, marks USED, returns short-lived R2 signed URL
```

This satisfies the requirement that paid books cannot be read before purchase, the download link expires on first successful use, and links also expire after 24 hours.

## Latest added features

- Free read-only upload formats: `.html`, `.txt`, `.pdf`
- Reader format modes: `CHAPTERS`, `TXT`, `HTML`, `PDF`
- Flexible storage config: `STORAGE_DRIVER=local` for free/simple deployments, `STORAGE_DRIVER=r2`/`s3` for private object storage
- Mock payment mode: `MOCK_BTCPAY=true` for free testing without a BTCPay server
- Local signed file route for private local storage
- Admin upload target API for local/R2 uploads
- Richer macOS + Netflix visual theme in `preview.html`
- Built-in About, Contact, Privacy Policy and Terms content
- New docs:
  - `docs/ENVIRONMENT.md`
  - `docs/HOSTING_FREE.md`
  - `docs/FREE_BOOK_UPLOADS.md`
  - `docs/LEGAL_PAGES.md`

## Simple free config

For a free development deployment, start with:

```env
STORAGE_DRIVER=local
MOCK_BTCPAY=true
```

For real sales, switch to:

```env
STORAGE_DRIVER=r2
MOCK_BTCPAY=false
```

See `docs/ENVIRONMENT.md` and `docs/HOSTING_FREE.md` for exact setup steps.


## Easiest setup guide

If you are confused about where to create values and where to paste them, open this file first:

```txt
docs/EASY_CONFIGURATION_STEP_BY_STEP.md
```

It explains exact steps for GitHub, PostgreSQL, BTCPay Server, R2/local storage, environment variable names, and what value to paste into each one.


## Option-by-option beginner setup

For the clearest setup format, use:

```txt
docs/SETUP_OPTIONS_BEGINNER.md
```

It is organized exactly as: Database Option 1/2/3, Hosting Option 1/2/3, Payment Option 1/2, Storage Option 1/2, with exact ENV keys and values.


## New recommended configuration guide

For the clearest option-by-option setup with website links and exact ENV variable names, use:

```txt
docs/CONFIGURATION_OPTIONS_WITH_LINKS.md
```

Readora now uses automatic config: deploy demo first with `BTCPAY_MODE=auto` and `STORAGE_DRIVER=auto`; later add BTCPay/R2 variables and it becomes production/live automatically.

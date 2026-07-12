# Readora Environment Variables

Readora is designed so you can push the repo to GitHub and configure everything from your hosting provider's **Environment Variables** screen. Do **not** commit `.env` to GitHub.

## Minimal free/local setup

Use this for local development, GitHub demos, and a free deployment without paid object storage:

```env
NODE_ENV=production
PORT=8080
APP_URL=https://your-readora-domain.example
DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/DB
COOKIE_SECRET=generate_a_long_random_string
JWT_SECRET=generate_a_different_long_random_string
CORS_ORIGIN=https://your-readora-domain.example

STORAGE_DRIVER=local
LOCAL_STORAGE_DIR=./storage
MOCK_BTCPAY=true
SIGNED_URL_SECONDS=300
DOWNLOAD_TOKEN_HOURS=24
```

With `STORAGE_DRIVER=local`, files are stored on the server filesystem. This is simple and free, but on some free hosts the filesystem can reset on redeploy. For real ebook sales, use private S3-compatible storage when possible.

With `MOCK_BTCPAY=true`, checkout uses mock invoices for testing. Set it to `false` when your BTCPay Server is ready.

## Production with BTCPay Server

```env
MOCK_BTCPAY=false
BTCPAY_URL=https://btcpay.yourdomain.com
BTCPAY_API_KEY=your_btcpay_api_key
BTCPAY_STORE_ID=your_store_id
BTCPAY_WEBHOOK_SECRET=your_webhook_secret
BTCPAY_CURRENCY=USD
```

### How to get BTCPay values

1. Log in to your BTCPay Server.
2. Create/select a store.
3. Store ID: Store settings → General → Store ID.
4. API key: Account → Manage account → API keys → Generate API key.
5. Give invoice permissions: create/view/modify invoices and webhook permissions.
6. Webhook secret: Store settings → Webhooks → create webhook for `https://YOUR_DOMAIN/api/webhooks/btcpay`.
7. Copy the secret into `BTCPAY_WEBHOOK_SECRET`.

## Private S3/R2 storage

If you use Cloudflare R2 or another S3-compatible free tier:

```env
STORAGE_DRIVER=r2
R2_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID=your_access_key
R2_SECRET_ACCESS_KEY=your_secret_key
R2_BUCKET=readora-private-ebooks
R2_REGION=auto
```

### How to get R2 values

1. Create a private bucket.
2. Do not enable public access.
3. Create an R2 API token/access key.
4. Copy endpoint, access key, secret key and bucket name into your hosting provider env vars.
5. Configure CORS for admin upload if you upload from browser.

## Generating secrets

Use one of these locally:

```bash
openssl rand -base64 48
node -e "console.log(crypto.randomBytes(48).toString('base64url'))"
```

Set different values for `COOKIE_SECRET` and `JWT_SECRET`.

## Admin bootstrap variables

Only needed when creating/resetting the first admin:

```env
ADMIN_EMAIL=admin@example.com
ADMIN_INITIAL_PASSWORD=a-long-random-password
```

Then run:

```bash
npm run admin:create
```

After admin creation, rotate/remove `ADMIN_INITIAL_PASSWORD` from the host if you do not need it anymore.


## New recommended configuration guide

For the clearest option-by-option setup with website links and exact ENV variable names, use:

```txt
docs/CONFIGURATION_OPTIONS_WITH_LINKS.md
```

Readora now uses automatic config: deploy demo first with `BTCPAY_MODE=auto` and `STORAGE_DRIVER=auto`; later add BTCPay/R2 variables and it becomes production/live automatically.

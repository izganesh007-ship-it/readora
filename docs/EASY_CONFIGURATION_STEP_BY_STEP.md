# Readora Easy Configuration Guide

This guide tells you **exactly what to create**, **where to copy it from**, and **which environment variable name to paste it into**.

You do not paste secrets inside the code. You paste them in your deployment platform under something like:

```txt
Project / Service → Settings → Environment Variables → Add Variable
```

Each variable has two boxes:

```txt
Key   = ENVIRONMENT_VARIABLE_NAME
Value = the value you copied/generated
```

Example:

```txt
Key   = BTCPAY_URL
Value = https://btcpay.yourdomain.com
```

---

## 0. Choose your mode

### Mode A — easiest free demo mode

Use this first if you only want the site running from GitHub quickly.

```env
MOCK_BTCPAY=true
STORAGE_DRIVER=local
```

In this mode:

- no real Bitcoin payment setup is required
- no Cloudflare R2 setup is required
- checkout uses mock payments
- files are stored in local server storage

Use file:

```txt
.env.demo.example
```

### Mode B — real production mode

Use this when you are ready to sell real paid ebooks.

```env
MOCK_BTCPAY=false
STORAGE_DRIVER=r2
```

In this mode you need:

- PostgreSQL database
- BTCPay Server store
- BTCPay API key
- BTCPay webhook secret
- private storage such as Cloudflare R2/S3

Use file:

```txt
.env.production.example
```

---

# PART 1 — GitHub setup

## Step 1. Create GitHub repository

1. Go to GitHub.
2. Click **New repository**.
3. Name it:

```txt
readora
```

4. Keep it private or public.
5. Upload/push the contents of the `readora` folder.

Important: do **not** upload your real `.env` file.

Safe to upload:

```txt
.env.example
.env.demo.example
.env.production.example
```

Not safe to upload:

```txt
.env
```

---

# PART 2 — Database setup

Readora needs PostgreSQL.

You can use any free PostgreSQL provider. Common free/dev choices include Neon, Supabase, Render PostgreSQL, Railway PostgreSQL, or a PostgreSQL database on your own VPS.

## Step 2. Create PostgreSQL database

1. Open your PostgreSQL provider.
2. Create a new project/database.
3. Find the connection string.

It usually looks like this:

```txt
postgresql://username:password@host/database?sslmode=require
```

## Step 3. Paste database URL into deployment env vars

In your hosting provider environment variables, add:

```txt
Key   = DATABASE_URL
Value = paste your PostgreSQL connection string
```

Example:

```txt
Key   = DATABASE_URL
Value = postgresql://readora:abc123@db.example.com/readora?sslmode=require
```

---

# PART 3 — Required base environment variables

Paste these in your deployment platform for every deployment.

## Step 4. Set app URL

After your first deployment, your host will give you a URL like:

```txt
https://readora-yourname.onrender.com
```

Paste it as:

```txt
Key   = APP_URL
Value = https://your-deployed-readora-url.com
```

Also paste the same URL as:

```txt
Key   = CORS_ORIGIN
Value = https://your-deployed-readora-url.com
```

Important: no trailing slash.

Correct:

```txt
https://readora.example.com
```

Wrong:

```txt
https://readora.example.com/
```

## Step 5. Generate secrets

On your computer terminal, run:

```bash
node -e "console.log(crypto.randomBytes(48).toString('base64url'))"
```

Run it two times.

Paste first result:

```txt
Key   = COOKIE_SECRET
Value = first generated random string
```

Paste second result:

```txt
Key   = JWT_SECRET
Value = second generated random string
```

## Step 6. Set Node environment

```txt
Key   = NODE_ENV
Value = production
```

## Step 7. Set port

Most hosts automatically set `PORT`. If your host asks for it, use:

```txt
Key   = PORT
Value = 8080
```

---

# PART 4 — Demo/free payment setup

If you do not have BTCPay yet, use mock mode.

Paste:

```txt
Key   = MOCK_BTCPAY
Value = true
```

This means:

- no BTCPay server required
- no Bitcoin required
- checkout is simulated
- good for testing/development

When you are ready for real payments, change it to:

```txt
Key   = MOCK_BTCPAY
Value = false
```

---

# PART 5 — Real BTCPay Server setup

Only do this when you are ready for real Bitcoin payments.

## Step 8. Get your BTCPay Server URL

Open your BTCPay Server in browser.

Example:

```txt
https://btcpay.yourdomain.com
```

Paste it as:

```txt
Key   = BTCPAY_URL
Value = https://btcpay.yourdomain.com
```

Important: paste only the main BTCPay domain.

Correct:

```txt
https://btcpay.yourdomain.com
```

Wrong:

```txt
https://btcpay.yourdomain.com/api/v1
```

## Step 9. Create/select BTCPay store

1. Log in to BTCPay Server.
2. Create a store or select an existing store.
3. Go to:

```txt
Store Settings → General
```

4. Find:

```txt
Store ID
```

Paste it as:

```txt
Key   = BTCPAY_STORE_ID
Value = paste Store ID here
```

## Step 10. Create BTCPay API key

In BTCPay Server:

1. Click your account/profile icon.
2. Go to:

```txt
Manage Account → API Keys
```

3. Click:

```txt
Generate API Key
```

4. Label it:

```txt
Readora Production
```

5. Select your Readora store.
6. Give these permissions:

```txt
btcpay.store.canviewinvoices
btcpay.store.cancreateinvoice
btcpay.store.canmodifyinvoices
btcpay.store.webhooks.canmodifywebhooks
btcpay.store.canviewstoresettings
```

7. Click create/generate.
8. Copy the generated API key/token.

Paste it as:

```txt
Key   = BTCPAY_API_KEY
Value = paste generated API key here
```

## Step 11. Create BTCPay webhook

In BTCPay Server:

1. Open your store.
2. Go to:

```txt
Store Settings → Webhooks
```

3. Click:

```txt
Create Webhook
```

4. Payload URL should be:

```txt
https://YOUR_READORA_APP_DOMAIN/api/webhooks/btcpay
```

Example:

```txt
https://readora.example.com/api/webhooks/btcpay
```

5. Events: choose invoice payment/settlement events, or choose **send everything** if you are unsure.
6. Copy the webhook secret.

Paste it as:

```txt
Key   = BTCPAY_WEBHOOK_SECRET
Value = paste webhook secret here
```

## Step 12. Set payment currency

Usually use:

```txt
Key   = BTCPAY_CURRENCY
Value = USD
```

## Step 13. Turn real payments on

After all BTCPay variables are added, set:

```txt
Key   = MOCK_BTCPAY
Value = false
```

Then redeploy/restart the app.

---

# PART 6 — Storage setup

Readora supports two simple storage modes.

## Option A: local storage, easiest/free demo

Paste:

```txt
Key   = STORAGE_DRIVER
Value = local
```

```txt
Key   = LOCAL_STORAGE_DIR
Value = ./storage
```

Use this for demos and testing.

Warning: many free hosts delete local uploaded files when the app redeploys/restarts. Do not rely on this for real paid ebook sales.

## Option B: Cloudflare R2 / S3 private storage, production

Use this for real sales.

### Step 14. Create private bucket

1. Go to your storage provider.
2. Create a bucket named:

```txt
readora-private-ebooks
```

3. Keep it private.
4. Do not enable public access.

### Step 15. Create storage API keys

In Cloudflare R2 or your S3 provider:

1. Open R2 / object storage settings.
2. Create access key.
3. Copy:

```txt
Endpoint
Access Key ID
Secret Access Key
Bucket Name
```

### Step 16. Paste storage env vars

Paste these:

```txt
Key   = STORAGE_DRIVER
Value = r2
```

```txt
Key   = R2_ENDPOINT
Value = paste endpoint here
```

```txt
Key   = R2_ACCESS_KEY_ID
Value = paste access key id here
```

```txt
Key   = R2_SECRET_ACCESS_KEY
Value = paste secret access key here
```

```txt
Key   = R2_BUCKET
Value = readora-private-ebooks
```

```txt
Key   = R2_REGION
Value = auto
```

---

# PART 7 — Download link settings

Paid ebook downloads are one-time only.

Set:

```txt
Key   = DOWNLOAD_TOKEN_HOURS
Value = 24
```

This means the one-time token expires after 24 hours.

Set:

```txt
Key   = SIGNED_URL_SECONDS
Value = 300
```

This means the actual private file URL expires after 5 minutes.

The paid download flow is:

```txt
Payment confirmed → one-time token created → customer redeems token once → token becomes USED forever
```

---

# PART 8 — Hosting from GitHub

Use any host that supports Node.js or Docker.

## Node build settings

If your host asks for commands:

```txt
Build Command = npm install && npm run build
Start Command = npm start
```

If your repo root contains the `readora` folder, set:

```txt
Root Directory = readora
```

If you pushed the contents of the `readora` folder directly, leave root directory blank.

## Docker settings

If your host supports Docker, it can use the included:

```txt
Dockerfile
```

You usually do not need custom build/start commands in Docker mode.

---

# PART 9 — Run database setup

After `DATABASE_URL` is configured, run these commands once.

From your computer:

```bash
cd readora
npm install
DATABASE_URL="paste-your-production-database-url" npm run db:migrate
DATABASE_URL="paste-your-production-database-url" npm run db:seed
```

Create first admin:

```bash
DATABASE_URL="paste-your-production-database-url" ADMIN_EMAIL="you@example.com" ADMIN_INITIAL_PASSWORD="make-a-long-password" npm run admin:create
```

If your host provides a shell/console, you can run the same commands there.

---

# PART 10 — Full environment variable checklist

## Required for all deployments

| Key | Value to paste |
|---|---|
| `NODE_ENV` | `production` |
| `APP_URL` | your deployed Readora URL |
| `CORS_ORIGIN` | same as APP_URL |
| `DATABASE_URL` | PostgreSQL connection string |
| `COOKIE_SECRET` | random generated secret |
| `JWT_SECRET` | another random generated secret |
| `SIGNED_URL_SECONDS` | `300` |
| `DOWNLOAD_TOKEN_HOURS` | `24` |

## Demo/free mode

| Key | Value |
|---|---|
| `MOCK_BTCPAY` | `true` |
| `STORAGE_DRIVER` | `local` |
| `LOCAL_STORAGE_DIR` | `./storage` |

## Real BTCPay mode

| Key | Value to paste |
|---|---|
| `MOCK_BTCPAY` | `false` |
| `BTCPAY_URL` | your BTCPay Server domain |
| `BTCPAY_API_KEY` | generated BTCPay API key |
| `BTCPAY_STORE_ID` | BTCPay Store ID |
| `BTCPAY_WEBHOOK_SECRET` | webhook secret from BTCPay |
| `BTCPAY_CURRENCY` | `USD` or your currency |

## R2/private storage mode

| Key | Value to paste |
|---|---|
| `STORAGE_DRIVER` | `r2` |
| `R2_ENDPOINT` | R2 endpoint |
| `R2_ACCESS_KEY_ID` | R2 access key ID |
| `R2_SECRET_ACCESS_KEY` | R2 secret key |
| `R2_BUCKET` | bucket name |
| `R2_REGION` | `auto` |

---

# PART 11 — Final test checklist

After deployment:

1. Open:

```txt
https://YOUR_APP_DOMAIN/health
```

You should see:

```json
{"ok":true,"service":"readora-api"}
```

2. Open your app home page.
3. Test Browse page.
4. Test free reader.
5. Test checkout in mock mode.
6. If using real BTCPay, make a tiny test payment.
7. Confirm one-time download works once.
8. Try same download token again — it should fail.

---

# Very simple example: demo env vars

Paste this first, replacing the obvious values:

```env
NODE_ENV=production
APP_URL=https://your-readora-app.example
CORS_ORIGIN=https://your-readora-app.example
DATABASE_URL=postgresql://username:password@host/db?sslmode=require
COOKIE_SECRET=paste-random-secret-1
JWT_SECRET=paste-random-secret-2
MOCK_BTCPAY=true
STORAGE_DRIVER=local
LOCAL_STORAGE_DIR=./storage
SIGNED_URL_SECONDS=300
DOWNLOAD_TOKEN_HOURS=24
```

# Very simple example: production env vars

```env
NODE_ENV=production
APP_URL=https://your-readora-app.example
CORS_ORIGIN=https://your-readora-app.example
DATABASE_URL=postgresql://username:password@host/db?sslmode=require
COOKIE_SECRET=paste-random-secret-1
JWT_SECRET=paste-random-secret-2
MOCK_BTCPAY=false
BTCPAY_URL=https://btcpay.yourdomain.com
BTCPAY_API_KEY=paste-btcpay-api-key
BTCPAY_STORE_ID=paste-btcpay-store-id
BTCPAY_WEBHOOK_SECRET=paste-btcpay-webhook-secret
BTCPAY_CURRENCY=USD
STORAGE_DRIVER=r2
R2_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID=paste-r2-access-key-id
R2_SECRET_ACCESS_KEY=paste-r2-secret-access-key
R2_BUCKET=readora-private-ebooks
R2_REGION=auto
SIGNED_URL_SECONDS=300
DOWNLOAD_TOKEN_HOURS=24
```


## New recommended configuration guide

For the clearest option-by-option setup with website links and exact ENV variable names, use:

```txt
docs/CONFIGURATION_OPTIONS_WITH_LINKS.md
```

Readora now uses automatic config: deploy demo first with `BTCPAY_MODE=auto` and `STORAGE_DRIVER=auto`; later add BTCPay/R2 variables and it becomes production/live automatically.

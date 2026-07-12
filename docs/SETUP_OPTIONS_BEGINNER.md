# Readora Setup Options — Beginner Friendly

Use this guide like a menu. For every section, choose **one option**.

Example:

```txt
1. Database     → choose Option 1 Neon OR Option 2 Supabase
2. Hosting      → choose Option 1 Render OR Option 2 Railway/Fly/VPS
3. Payments     → choose Option 1 Mock first, later Option 2 BTCPay
4. Storage      → choose Option 1 Local first, later Option 2 Cloudflare R2
```

For every option, I show:

```txt
Where to create it
What to copy
Which ENV key to paste it into
```

---

# 1. Database

Readora uses PostgreSQL.

You only need **one** PostgreSQL database.

## Database — Option 1: Neon PostgreSQL, easiest recommended free option

Use this if you want the simplest hosted PostgreSQL setup.

### Step 1. Create Neon account

Go to Neon and create a free account.

### Step 2. Create project

Click:

```txt
New Project
```

Choose any project name, for example:

```txt
readora
```

### Step 3. Copy connection string

In Neon dashboard, find:

```txt
Connection string
```

It looks like:

```txt
postgresql://username:password@ep-something.region.aws.neon.tech/dbname?sslmode=require
```

### Step 4. Paste into deployment ENV

In your hosting provider:

```txt
Settings → Environment Variables → Add Variable
```

Add:

```txt
Key   = DATABASE_URL
Value = paste Neon connection string here
```

Example:

```txt
Key   = DATABASE_URL
Value = postgresql://readora_owner:abc123@ep-red-snow.us-east-1.aws.neon.tech/readora?sslmode=require
```

Done.

---

## Database — Option 2: Supabase PostgreSQL

Use this if you already like Supabase.

### Step 1. Create Supabase project

Create a Supabase account and make a new project.

### Step 2. Open database settings

Go to:

```txt
Project Settings → Database
```

### Step 3. Copy connection string

Look for:

```txt
Connection string → URI
```

It looks like:

```txt
postgresql://postgres:[YOUR-PASSWORD]@db.xxxxx.supabase.co:5432/postgres
```

Replace `[YOUR-PASSWORD]` with your actual database password.

### Step 4. Paste into deployment ENV

```txt
Key   = DATABASE_URL
Value = paste Supabase PostgreSQL URI here
```

---

## Database — Option 3: Your own PostgreSQL server

Use this if you have a VPS/server.

Your value should look like:

```txt
postgresql://readora:yourpassword@your-server-ip:5432/readora
```

Paste:

```txt
Key   = DATABASE_URL
Value = your PostgreSQL connection string
```

---

# 2. Hosting

You only need **one** hosting provider.

## Hosting — Option 1: Render-style Node service, easiest

Use this if your host supports GitHub deployment and Node.js.

### Step 1. Push code to GitHub

Push the `readora` project to GitHub.

### Step 2. Create web service

In hosting dashboard:

```txt
New Web Service → Connect GitHub repo
```

### Step 3. Root directory

If your GitHub repo contains the folder named `readora`, set:

```txt
Root Directory = readora
```

If your repo directly contains `package.json`, leave root blank.

### Step 4. Build command

Paste:

```txt
npm install && npm run build
```

### Step 5. Start command

Paste:

```txt
npm start
```

### Step 6. Add ENV variables

Add env vars from the sections below.

---

## Hosting — Option 2: Docker hosting

Use this if your host supports Docker.

Readora already has:

```txt
Dockerfile
```

You only need to connect GitHub and set env variables.

No custom build/start command is usually needed.

---

## Hosting — Option 3: VPS/self-host

Use this if you have your own Linux server.

```bash
git clone YOUR_GITHUB_REPO_URL
cd readora
cp .env.production.example .env
# edit .env values
npm install
npm run build
npm start
```

For HTTPS, put it behind Caddy/Nginx/Cloudflare.

---

# 3. Basic required ENV variables

These are required for every option.

## Step 1. NODE_ENV

Paste:

```txt
Key   = NODE_ENV
Value = production
```

## Step 2. APP_URL

After deployment, your host gives you a URL.

Example:

```txt
https://readora-demo.onrender.com
```

Paste:

```txt
Key   = APP_URL
Value = https://your-readora-app-url
```

Do not add `/` at the end.

Correct:

```txt
https://readora-demo.onrender.com
```

Wrong:

```txt
https://readora-demo.onrender.com/
```

## Step 3. CORS_ORIGIN

Paste the same URL:

```txt
Key   = CORS_ORIGIN
Value = https://your-readora-app-url
```

## Step 4. COOKIE_SECRET

Generate random secret.

Run this on your computer:

```bash
node -e "console.log(crypto.randomBytes(48).toString('base64url'))"
```

Copy the result.

Paste:

```txt
Key   = COOKIE_SECRET
Value = paste generated random secret here
```

## Step 5. JWT_SECRET

Run the command again:

```bash
node -e "console.log(crypto.randomBytes(48).toString('base64url'))"
```

Copy the new result.

Paste:

```txt
Key   = JWT_SECRET
Value = paste second generated random secret here
```

Important: `COOKIE_SECRET` and `JWT_SECRET` should be different.

---

# 4. Payment

Choose only one option first.

## Payment — Option 1: Mock payment, easiest for first deployment

Use this first.

No BTCPay account needed.

Paste:

```txt
Key   = MOCK_BTCPAY
Value = true
```

This lets you test checkout without Bitcoin.

Do not add BTCPay env vars yet.

---

## Payment — Option 2: Real BTCPay Server payment

Use this when you are ready for real Bitcoin payments.

### Step 1. Open BTCPay Server

Your BTCPay URL looks like:

```txt
https://btcpay.yourdomain.com
```

Paste:

```txt
Key   = BTCPAY_URL
Value = https://btcpay.yourdomain.com
```

Do not include `/api/v1`.

### Step 2. Create/select BTCPay store

In BTCPay:

```txt
Stores → Create Store
```

or select your existing store.

### Step 3. Copy Store ID

Go to:

```txt
Store Settings → General → Store ID
```

Copy Store ID.

Paste:

```txt
Key   = BTCPAY_STORE_ID
Value = paste Store ID here
```

### Step 4. Create API key

In BTCPay:

```txt
Account → Manage Account → API Keys → Generate API Key
```

Name/label:

```txt
Readora Production
```

Select your store.

Enable these permissions:

```txt
btcpay.store.canviewinvoices
btcpay.store.cancreateinvoice
btcpay.store.canmodifyinvoices
btcpay.store.webhooks.canmodifywebhooks
btcpay.store.canviewstoresettings
```

Copy the generated API key.

Paste:

```txt
Key   = BTCPAY_API_KEY
Value = paste generated BTCPay API key here
```

### Step 5. Create webhook

In BTCPay:

```txt
Store Settings → Webhooks → Create Webhook
```

Payload URL:

```txt
https://YOUR_READORA_APP_URL/api/webhooks/btcpay
```

Example:

```txt
https://readora.example.com/api/webhooks/btcpay
```

Events:

```txt
Invoice settled / payment settled
```

If unsure, choose:

```txt
Send everything
```

Copy webhook secret.

Paste:

```txt
Key   = BTCPAY_WEBHOOK_SECRET
Value = paste webhook secret here
```

### Step 6. Set currency

Paste:

```txt
Key   = BTCPAY_CURRENCY
Value = USD
```

### Step 7. Turn off mock mode

Paste/change:

```txt
Key   = MOCK_BTCPAY
Value = false
```

---

# 5. Ebook file storage

Choose one option.

## Storage — Option 1: Local storage, easiest free demo

Use this for first deployment/testing.

Paste:

```txt
Key   = STORAGE_DRIVER
Value = local
```

Paste:

```txt
Key   = LOCAL_STORAGE_DIR
Value = ./storage
```

Warning: many free hosts remove local files after redeploy. Use this for demo, not serious paid sales.

---

## Storage — Option 2: Cloudflare R2 private bucket

Use this for real paid ebook files.

### Step 1. Create R2 bucket

In Cloudflare dashboard:

```txt
R2 Object Storage → Create bucket
```

Bucket name:

```txt
readora-private-ebooks
```

Keep bucket private.

### Step 2. Copy bucket name

Paste:

```txt
Key   = R2_BUCKET
Value = readora-private-ebooks
```

### Step 3. Get R2 endpoint

In Cloudflare R2, find S3 API endpoint.

It looks like:

```txt
https://ACCOUNT_ID.r2.cloudflarestorage.com
```

Paste:

```txt
Key   = R2_ENDPOINT
Value = paste R2 endpoint here
```

### Step 4. Create R2 API token/access key

In Cloudflare:

```txt
R2 → Manage R2 API Tokens → Create API Token
```

Give access to your bucket.

Copy:

```txt
Access Key ID
Secret Access Key
```

Paste:

```txt
Key   = R2_ACCESS_KEY_ID
Value = paste Access Key ID here
```

Paste:

```txt
Key   = R2_SECRET_ACCESS_KEY
Value = paste Secret Access Key here
```

### Step 5. Set driver and region

Paste:

```txt
Key   = STORAGE_DRIVER
Value = r2
```

Paste:

```txt
Key   = R2_REGION
Value = auto
```

---

# 6. Download security settings

These control one-time download behavior.

Paste:

```txt
Key   = DOWNLOAD_TOKEN_HOURS
Value = 24
```

Meaning: download token expires after 24 hours.

Paste:

```txt
Key   = SIGNED_URL_SECONDS
Value = 300
```

Meaning: actual private file URL expires after 5 minutes.

Paid ebook download is still one-time only.

---

# 7. Free books upload choices

Readora supports free read-only books in these formats:

```txt
.html
.txt
.pdf
chapters
```

When creating a free book from admin/API, choose one reader format:

```txt
readerFormat = HTML
readerFormat = TXT
readerFormat = PDF
readerFormat = CHAPTERS
```

If it is a free read-only book, set:

```txt
access = FREE
priceCents = 0
allowFreeDownload = false
```

If you want users to download a free book, set:

```txt
allowFreeDownload = true
```

---

# 8. Database migration and seed

After deployment env vars are added, run this once.

From your computer:

```bash
cd readora
npm install
DATABASE_URL="paste DATABASE_URL here" npm run db:migrate
DATABASE_URL="paste DATABASE_URL here" npm run db:seed
```

---

# 9. Create first admin

Run this once:

```bash
DATABASE_URL="paste DATABASE_URL here" ADMIN_EMAIL="your@email.com" ADMIN_INITIAL_PASSWORD="your-long-password" npm run admin:create
```

Then login with that email/password.

---

# 10. Exact ENV variable templates

## Template A: first free demo deployment

Paste these in your hosting provider:

```env
NODE_ENV=production
APP_URL=https://your-readora-app-url
CORS_ORIGIN=https://your-readora-app-url
DATABASE_URL=postgresql://paste-your-db-url
COOKIE_SECRET=paste-random-secret-1
JWT_SECRET=paste-random-secret-2
MOCK_BTCPAY=true
STORAGE_DRIVER=local
LOCAL_STORAGE_DIR=./storage
SIGNED_URL_SECONDS=300
DOWNLOAD_TOKEN_HOURS=24
```

## Template B: real production deployment

Paste these:

```env
NODE_ENV=production
APP_URL=https://your-readora-app-url
CORS_ORIGIN=https://your-readora-app-url
DATABASE_URL=postgresql://paste-your-db-url
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

---

# 11. Final test

Open:

```txt
https://YOUR_READORA_APP_URL/health
```

Expected:

```json
{"ok":true,"service":"readora-api"}
```

Then test:

1. homepage
2. browse books
3. free reader
4. mock checkout or BTCPay checkout
5. purchase success
6. download token once
7. retry same token — it should fail


## New recommended configuration guide

For the clearest option-by-option setup with website links and exact ENV variable names, use:

```txt
docs/CONFIGURATION_OPTIONS_WITH_LINKS.md
```

Readora now uses automatic config: deploy demo first with `BTCPAY_MODE=auto` and `STORAGE_DRIVER=auto`; later add BTCPay/R2 variables and it becomes production/live automatically.

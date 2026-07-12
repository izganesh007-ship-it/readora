# Readora Configuration Options With Links

This is the main setup guide.

You asked for a simple structure like:

```txt
1. Database
   Option 1
   Option 2

2. Hosting
   Option 1
   Option 2

3. Payments
   Option 1
   Option 2
```

This guide gives you exactly that.

It also explains the new **automatic configuration**:

> Deploy demo first. Later add BTCPay/R2 environment variables. Readora automatically becomes production/live. No separate demo/production headache.

---

# Very Important: Automatic Demo → Production Upgrade

Readora now works like this:

## First deploy, demo mode

You paste only basic variables:

```env
BTCPAY_MODE=auto
STORAGE_DRIVER=auto
```

If BTCPay keys are missing, Readora automatically uses mock/demo checkout.

If R2/S3 keys are missing, Readora automatically uses local storage.

## Later, production mode

You only add these BTCPay variables:

```env
BTCPAY_URL=...
BTCPAY_API_KEY=...
BTCPAY_STORE_ID=...
BTCPAY_WEBHOOK_SECRET=...
```

Readora automatically switches to real BTCPay.

You only add these R2 variables:

```env
R2_ENDPOINT=...
R2_ACCESS_KEY_ID=...
R2_SECRET_ACCESS_KEY=...
R2_BUCKET=...
```

Readora automatically switches to private R2 storage.

You do **not** need to change a demo flag to production.

Keep these as:

```env
BTCPAY_MODE=auto
STORAGE_DRIVER=auto
CONFIG_AUTO_UPGRADE=true
```

---

# 1. Database

Readora needs PostgreSQL.

You choose **one** database option.

---

## Database Option 1: Neon PostgreSQL — recommended easiest free option

Website:

```txt
https://neon.tech
```

Best for:

```txt
Beginner-friendly free PostgreSQL hosting.
```

### What you need from Neon

You need:

```txt
PostgreSQL connection string
```

This becomes your `DATABASE_URL`.

### How to create it

1. Go to:

```txt
https://neon.tech
```

2. Sign up / log in.
3. Click:

```txt
New Project
```

4. Project name:

```txt
readora
```

5. After project creation, open:

```txt
Dashboard → Connection Details
```

6. Copy the connection string.

It looks like:

```txt
postgresql://username:password@ep-something.region.aws.neon.tech/dbname?sslmode=require
```

### Where to paste it in deployment

In your hosting provider:

```txt
Project → Settings → Environment Variables → Add Variable
```

Paste:

```txt
Key   = DATABASE_URL
Value = paste Neon connection string here
```

Example:

```txt
Key   = DATABASE_URL
Value = postgresql://readora_owner:abc123@ep-red-snow.us-east-1.aws.neon.tech/readora?sslmode=require
```

---

## Database Option 2: Supabase PostgreSQL

Website:

```txt
https://supabase.com
```

Best for:

```txt
Free PostgreSQL plus optional dashboard/tools.
```

### What you need from Supabase

You need:

```txt
PostgreSQL URI / connection string
```

This becomes your `DATABASE_URL`.

### How to create it

1. Go to:

```txt
https://supabase.com
```

2. Create new project.
3. Save your database password.
4. Open:

```txt
Project Settings → Database
```

5. Find:

```txt
Connection string → URI
```

6. Copy it.

It looks like:

```txt
postgresql://postgres:[YOUR-PASSWORD]@db.xxxxx.supabase.co:5432/postgres
```

7. Replace `[YOUR-PASSWORD]` with your actual password.

### Where to paste it

```txt
Key   = DATABASE_URL
Value = paste Supabase PostgreSQL URI here
```

---

## Database Option 3: Render PostgreSQL, if available in your plan

Website:

```txt
https://render.com
```

Best for:

```txt
Keeping app and database on same platform.
```

Note: free database availability can change. Check Render's current pricing before choosing this.

### What you need

You need:

```txt
External Database URL
```

### How to get it

1. Go to:

```txt
https://render.com
```

2. Create PostgreSQL database.
3. Open database dashboard.
4. Copy:

```txt
External Database URL
```

### Where to paste it

```txt
Key   = DATABASE_URL
Value = paste Render External Database URL here
```

---

## Database Option 4: Your own PostgreSQL server

Website/software:

```txt
https://www.postgresql.org
```

Best for:

```txt
VPS/self-hosted deployment.
```

Your connection string looks like:

```txt
postgresql://readora:yourpassword@your-server-ip:5432/readora
```

Paste:

```txt
Key   = DATABASE_URL
Value = your PostgreSQL connection string
```

---

# 2. Hosting / Deployment

Choose **one** hosting option.

---

## Hosting Option 1: Render Web Service

Website:

```txt
https://render.com
```

Best for:

```txt
Beginner GitHub deployment.
```

### How to deploy

1. Push Readora code to GitHub.
2. Go to Render.
3. Click:

```txt
New → Web Service
```

4. Connect your GitHub repository.
5. If your repository contains a folder called `readora`, set:

```txt
Root Directory = readora
```

If your repo directly contains `package.json`, leave root directory blank.

6. Build command:

```txt
npm install && npm run build
```

7. Start command:

```txt
npm start
```

8. Add environment variables from this guide.

---

## Hosting Option 2: Railway

Website:

```txt
https://railway.app
```

Best for:

```txt
Simple GitHub deploy with env variables.
```

### How to deploy

1. Push code to GitHub.
2. Create new Railway project.
3. Select:

```txt
Deploy from GitHub repo
```

4. Add environment variables.
5. Build command if needed:

```txt
npm install && npm run build
```

6. Start command if needed:

```txt
npm start
```

---

## Hosting Option 3: Koyeb

Website:

```txt
https://www.koyeb.com
```

Best for:

```txt
Docker/Node app deployment with GitHub.
```

### How to deploy

1. Create service from GitHub.
2. Choose Dockerfile or Node build.
3. Add environment variables.
4. Deploy.

---

## Hosting Option 4: Fly.io

Website:

```txt
https://fly.io
```

Best for:

```txt
Docker deployment and more control.
```

Readora includes:

```txt
Dockerfile
```

Use Docker deployment and paste environment variables as secrets.

---

## Hosting Option 5: VPS / self-hosting

Examples:

```txt
Any Linux VPS
```

Best for:

```txt
Full control and production BTCPay/self-hosting.
```

Commands:

```bash
git clone YOUR_REPO_URL
cd readora
npm install
npm run build
npm start
```

Use Caddy/Nginx/Cloudflare for HTTPS.

---

# 3. Basic Required Configuration

These are always required.

---

## Config 1: NODE_ENV

Paste:

```txt
Key   = NODE_ENV
Value = production
```

---

## Config 2: APP_URL

Your deployed app URL.

Example:

```txt
https://readora-demo.onrender.com
```

Paste:

```txt
Key   = APP_URL
Value = https://your-readora-app-url
```

No trailing slash.

---

## Config 3: CORS_ORIGIN

Use same URL as `APP_URL`.

Paste:

```txt
Key   = CORS_ORIGIN
Value = https://your-readora-app-url
```

---

## Config 4: COOKIE_SECRET

Generate this on your computer:

```bash
node -e "console.log(crypto.randomBytes(48).toString('base64url'))"
```

Paste:

```txt
Key   = COOKIE_SECRET
Value = generated random string
```

---

## Config 5: JWT_SECRET

Run again:

```bash
node -e "console.log(crypto.randomBytes(48).toString('base64url'))"
```

Paste:

```txt
Key   = JWT_SECRET
Value = second generated random string
```

Use a different value from `COOKIE_SECRET`.

---

# 4. Payment Configuration

Choose one payment option.

---

## Payment Option 1: Automatic mock checkout — easiest first deploy

Website:

```txt
No website needed
```

No API keys needed.

Paste:

```txt
Key   = BTCPAY_MODE
Value = auto
```

If BTCPay variables are missing, Readora uses demo checkout automatically.

Later when you add BTCPay variables, Readora becomes live automatically.

---

## Payment Option 2: BTCPay Server self-hosted

Website:

```txt
https://btcpayserver.org
```

Deployment docs:

```txt
https://docs.btcpayserver.org/Deployment/
```

Best for:

```txt
Real Bitcoin payments with no payment middleman.
```

### What you need from BTCPay

You need four values:

```txt
BTCPAY_URL
BTCPAY_STORE_ID
BTCPAY_API_KEY
BTCPAY_WEBHOOK_SECRET
```

---

### Step 1. Get BTCPAY_URL

Open your BTCPay Server in browser.

Example:

```txt
https://btcpay.yourdomain.com
```

Paste:

```txt
Key   = BTCPAY_URL
Value = https://btcpay.yourdomain.com
```

Do not paste `/api/v1`.

Correct:

```txt
https://btcpay.yourdomain.com
```

Wrong:

```txt
https://btcpay.yourdomain.com/api/v1
```

---

### Step 2. Get BTCPAY_STORE_ID

In BTCPay:

```txt
Store → Settings → General → Store ID
```

Copy Store ID.

Paste:

```txt
Key   = BTCPAY_STORE_ID
Value = paste Store ID here
```

---

### Step 3. Create BTCPAY_API_KEY

In BTCPay:

```txt
Account → Manage Account → API Keys → Generate API Key
```

Label:

```txt
Readora Production
```

Choose/select your store.

Enable permissions:

```txt
btcpay.store.canviewinvoices
btcpay.store.cancreateinvoice
btcpay.store.canmodifyinvoices
btcpay.store.webhooks.canmodifywebhooks
btcpay.store.canviewstoresettings
```

Copy generated API key.

Paste:

```txt
Key   = BTCPAY_API_KEY
Value = paste generated BTCPay API key here
```

---

### Step 4. Create BTCPAY_WEBHOOK_SECRET

In BTCPay:

```txt
Store → Settings → Webhooks → Create Webhook
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

---

### Step 5. Currency

Paste:

```txt
Key   = BTCPAY_CURRENCY
Value = USD
```

---

## Payment Option 3: Third-party hosted BTCPay

BTCPay third-party hosting docs:

```txt
https://docs.btcpayserver.org/Deployment/ThirdPartyHosting/
```

Use this if you do not want to host your own BTCPay server.

After you get access to hosted BTCPay, use the same steps as Option 2:

```txt
BTCPAY_URL
BTCPAY_STORE_ID
BTCPAY_API_KEY
BTCPAY_WEBHOOK_SECRET
```

---

# 5. Ebook Storage Configuration

Choose one storage option.

---

## Storage Option 1: Automatic local storage — easiest first deploy

Website:

```txt
No website needed
```

Paste:

```txt
Key   = STORAGE_DRIVER
Value = auto
```

Paste:

```txt
Key   = LOCAL_STORAGE_DIR
Value = ./storage
```

If R2 variables are missing, Readora uses local storage automatically.

Later when you add R2 variables, Readora switches to R2 automatically.

---

## Storage Option 2: Cloudflare R2 private storage — recommended production

Website:

```txt
https://dash.cloudflare.com
```

Direct product page:

```txt
https://www.cloudflare.com/developer-platform/products/r2/
```

Best for:

```txt
Private ebook files with signed URLs.
```

### What you need from R2

You need:

```txt
R2_ENDPOINT
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
R2_BUCKET
R2_REGION
```

---

### Step 1. Create bucket

In Cloudflare dashboard:

```txt
R2 Object Storage → Create bucket
```

Bucket name:

```txt
readora-private-ebooks
```

Keep it private.

Paste:

```txt
Key   = R2_BUCKET
Value = readora-private-ebooks
```

---

### Step 2. Get R2_ENDPOINT

In Cloudflare R2, find your S3 API endpoint.

It looks like:

```txt
https://ACCOUNT_ID.r2.cloudflarestorage.com
```

Paste:

```txt
Key   = R2_ENDPOINT
Value = paste endpoint here
```

---

### Step 3. Create access key

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

Paste Access Key ID:

```txt
Key   = R2_ACCESS_KEY_ID
Value = paste access key ID here
```

Paste Secret Access Key:

```txt
Key   = R2_SECRET_ACCESS_KEY
Value = paste secret access key here
```

---

### Step 4. Set region

Paste:

```txt
Key   = R2_REGION
Value = auto
```

---

## Storage Option 3: Backblaze B2 S3-compatible storage

Website:

```txt
https://www.backblaze.com/cloud-storage
```

Use this only if you prefer Backblaze.

You still paste the values into the same env names:

```txt
STORAGE_DRIVER=s3
R2_ENDPOINT=your Backblaze S3 endpoint
R2_ACCESS_KEY_ID=your key id
R2_SECRET_ACCESS_KEY=your application key
R2_BUCKET=your bucket name
R2_REGION=your region
```

The env names are called `R2_*` in Readora, but they work for S3-compatible storage too.

---

# 6. One-Time Download Configuration

Paid downloads are one-time only by database logic.

Paste:

```txt
Key   = DOWNLOAD_TOKEN_HOURS
Value = 24
```

This means token expires after 24 hours.

Paste:

```txt
Key   = SIGNED_URL_SECONDS
Value = 300
```

This means the private file URL expires after 5 minutes.

Flow:

```txt
Payment paid → one-time token issued → token redeemed once → token becomes USED forever
```

---

# 7. Free Book Upload Configuration

Free books can be uploaded/read as:

```txt
HTML
TXT
PDF
CHAPTERS
```

For a free read-only book:

```json
{
  "access": "FREE",
  "priceCents": 0,
  "readerFormat": "HTML",
  "allowFreeDownload": false
}
```

For free TXT:

```json
{
  "access": "FREE",
  "priceCents": 0,
  "readerFormat": "TXT",
  "allowFreeDownload": false
}
```

For free PDF read-only:

```json
{
  "access": "FREE",
  "priceCents": 0,
  "readerFormat": "PDF",
  "readerContentKey": "reader-pdf/your-book.pdf",
  "allowFreeDownload": false
}
```

Note: any PDF shown in browser can technically be saved or screen-captured by users. Readora protects the file from public direct access using signed private URLs, but no browser reader can fully prevent copying visible content.

---

# 8. Admin Account

You create the first admin once.

Run this from your computer or hosting shell:

```bash
DATABASE_URL="paste DATABASE_URL here" ADMIN_EMAIL="you@example.com" ADMIN_INITIAL_PASSWORD="your-long-password" npm run admin:create
```

Then log in with:

```txt
Email    = you@example.com
Password = your-long-password
```

---

# 9. Database Migration and Demo Seed

Run once after database is ready:

```bash
DATABASE_URL="paste DATABASE_URL here" npm run db:migrate
```

Optional demo books:

```bash
DATABASE_URL="paste DATABASE_URL here" npm run db:seed
```

---

# 10. Exact Environment Variable Templates

## Template A: first demo deployment

Paste these first:

```env
NODE_ENV=production
APP_URL=https://your-readora-app-url
CORS_ORIGIN=https://your-readora-app-url
DATABASE_URL=postgresql://paste-your-db-url
COOKIE_SECRET=paste-random-secret-1
JWT_SECRET=paste-random-secret-2
BTCPAY_MODE=auto
STORAGE_DRIVER=auto
LOCAL_STORAGE_DIR=./storage
CONFIG_AUTO_UPGRADE=true
SIGNED_URL_SECONDS=300
DOWNLOAD_TOKEN_HOURS=24
```

This deploys as demo automatically.

No BTCPay keys yet.

No R2 keys yet.

---

## Template B: upgrade same deployment to production

Do not remove the previous variables.

Just add these BTCPay variables:

```env
BTCPAY_URL=https://btcpay.yourdomain.com
BTCPAY_API_KEY=paste-btcpay-api-key
BTCPAY_STORE_ID=paste-btcpay-store-id
BTCPAY_WEBHOOK_SECRET=paste-btcpay-webhook-secret
BTCPAY_CURRENCY=USD
```

And add these R2 variables:

```env
R2_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID=paste-r2-access-key-id
R2_SECRET_ACCESS_KEY=paste-r2-secret-access-key
R2_BUCKET=readora-private-ebooks
R2_REGION=auto
```

Redeploy/restart.

Readora automatically becomes production/live because:

```env
BTCPAY_MODE=auto
STORAGE_DRIVER=auto
```

---

# 11. Final Test

Open:

```txt
https://YOUR_READORA_APP_URL/health
```

Expected:

```json
{"ok":true,"service":"readora-api"}
```

Then test:

1. Home page
2. Browse books
3. Free reader
4. Demo checkout first
5. Add BTCPay variables
6. Real checkout
7. Paid download once
8. Try same token again — it should fail

---

# 12. Quick Decision Recommendation

If you are beginner, choose this stack first:

```txt
Database: Neon
Hosting: Render or Railway
Payment: BTCPAY_MODE=auto, no BTCPay keys at first
Storage: STORAGE_DRIVER=auto, no R2 keys at first
```

Then later upgrade:

```txt
Payment: Add BTCPay vars
Storage: Add Cloudflare R2 vars
```

No rebuild of the app logic is needed.

# Readora Deployment Guide

## Recommended stack

- Frontend/API: Docker container on Fly.io, Render, Railway, AWS ECS, Hetzner or any VPS
- Database: Managed PostgreSQL 16+
- Storage: Cloudflare R2 private bucket
- Payments: BTCPay Server 2.0+ on your domain
- TLS: Cloudflare, Caddy, Traefik or platform-managed HTTPS

## Steps

1. Create PostgreSQL database.
2. Create private R2 bucket. Do **not** enable public bucket access.
3. Create BTCPay store, connect wallet and create API key with invoice permissions.
4. Configure BTCPay webhook to `https://yourdomain.com/api/webhooks/btcpay` and copy the webhook secret.
5. Copy `.env.example` to production env vars and set strong secrets.
6. Run migrations:

```bash
psql "$DATABASE_URL" -f sql/init.sql
psql "$DATABASE_URL" -f sql/seed.sql # optional demo data
ADMIN_EMAIL=admin@example.com ADMIN_INITIAL_PASSWORD='long-random-password' npm run admin:create
```

7. Build and run Docker image:

```bash
docker build -t readora .
docker run --env-file .env -p 8080:8080 readora
```

## HTTPS only

Run behind HTTPS and set `NODE_ENV=production`. Cookies become secure and HSTS is enabled.

## R2 CORS for admin upload

Configure R2 bucket CORS for PUT from your admin domain only. Example:

```json
[
  {
    "AllowedOrigins": ["https://yourdomain.com"],
    "AllowedMethods": ["PUT"],
    "AllowedHeaders": ["content-type"],
    "MaxAgeSeconds": 300
  }
]
```

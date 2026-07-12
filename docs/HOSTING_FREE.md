# Free / Low-Cost Hosting Guide for GitHub Deployment

The goal is: push Readora to GitHub, connect the repo to a host, then add environment variables in the host dashboard.

Free tiers change often, so verify current limits before launch. The following options are commonly used for no-cost development or small demos.

## Option A: Render-style web service + free Postgres

1. Push the `readora` folder to GitHub.
2. Create a new Web Service from the GitHub repo.
3. Runtime: Docker, or Node.
4. Build command if Node: `npm install && npm run build`
5. Start command if Node: `npm start`
6. Add environment variables from `docs/ENVIRONMENT.md`.
7. Create/connect a free PostgreSQL database if available.
8. Run migrations from the provider shell or locally against the remote database:

```bash
psql "$DATABASE_URL" -f sql/init.sql
psql "$DATABASE_URL" -f sql/seed.sql
ADMIN_EMAIL=you@example.com ADMIN_INITIAL_PASSWORD='long-password' npm run admin:create
```

## Option B: Fly.io / VPS / self-hosted Docker

```bash
docker build -t readora .
docker run --env-file .env -p 8080:8080 readora
```

Use a reverse proxy with HTTPS, such as Caddy:

```caddyfile
yourdomain.com {
  reverse_proxy localhost:8080
}
```

## Option C: Static preview only

If you only want to show the design first:

1. Deploy `preview.html` or `public/index.html` to GitHub Pages, Netlify, Cloudflare Pages or Vercel.
2. This is a static preview and does not run the backend/payment/download logic.

## Free configuration recommendations

For development or demo:

```env
STORAGE_DRIVER=local
MOCK_BTCPAY=true
```

For real sales:

```env
STORAGE_DRIVER=r2
MOCK_BTCPAY=false
```

BTCPay Server software is free/open-source. Hosting a production BTCPay instance may require your own server or a community/third-party host. Always test with a tiny payment before going live.

## GitHub checklist

- Commit source files, docs, SQL, Dockerfile.
- Do not commit `.env`.
- Add `.env.example` so hosts know the variable names.
- Add all real secrets in the hosting provider dashboard only.
- Run migrations after database creation.
- Create the first admin.
- Test `/health`, checkout, webhook, and one-time download redemption.


## New recommended configuration guide

For the clearest option-by-option setup with website links and exact ENV variable names, use:

```txt
docs/CONFIGURATION_OPTIONS_WITH_LINKS.md
```

Readora now uses automatic config: deploy demo first with `BTCPAY_MODE=auto` and `STORAGE_DRIVER=auto`; later add BTCPay/R2 variables and it becomes production/live automatically.

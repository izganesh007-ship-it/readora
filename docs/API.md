# Readora API

The API is REST-first and returns JSON.

## Storefront

- `GET /api/home`
- `GET /api/books?q=&category=&access=&sort=&page=&limit=`
- `GET /api/books/:slug`
- `GET /api/categories`
- `GET /api/reader/:slug`
- `PUT /api/reader/:slug/progress`

## Checkout

- `POST /api/checkout/btcpay`
- `POST /api/webhooks/btcpay`
- `GET /api/purchases/:id?accessToken=...`
- `POST /api/purchases/:id/download-token`
- `POST /api/downloads/:token/redeem`

## Admin

- `POST /api/admin/login`
- `POST /api/admin/logout`
- `GET /api/admin/analytics`
- `POST /api/admin/books`
- `POST /api/admin/uploads/sign`

See `openapi.yaml` for a machine-readable contract.

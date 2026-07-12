# Security Model

Readora is designed to sell paid ebooks without exposing private ebook files.

## Paid download flow

1. Customer creates BTCPay invoice.
2. BTCPay calls `/api/webhooks/btcpay`.
3. Webhook HMAC signature is verified with `BTCPAY_WEBHOOK_SECRET`.
4. Purchase is marked `PAID` in PostgreSQL.
5. Customer uses purchase access token to request a one-time download token.
6. Token is stored only as SHA-256 hash.
7. `/api/downloads/:token/redeem` uses a DB transaction and row lock.
8. If active and not expired, token status changes to `USED` immediately.
9. API returns a short-lived R2 signed URL.
10. Reuse of the same token returns expired/used.

## Admin security

- Argon2id password hashing
- Account lockout after repeated failures
- Rate-limited login endpoint
- Short admin session lifetime
- Role-based authorization
- Optional TOTP-ready schema
- Audit logging for sensitive events

## Web security

- Helmet security headers
- Content Security Policy
- HSTS in production
- strict CORS
- parameterized SQL queries
- no public ebook bucket
- signed URLs expire quickly
- no direct object keys exposed to customers until redemption

## Production hardening checklist

- Rotate all default secrets
- Use a managed WAF/CDN
- Enable database backups and PITR
- Monitor audit logs
- Enable BTCPay test payment before launch
- Keep Node dependencies updated
- Enforce admin 2FA for OWNER role

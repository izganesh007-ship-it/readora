import crypto from 'node:crypto';
import { env } from '../config/env.js';
function apiUrl(path) {
    if (!env.BTCPAY_URL || !env.BTCPAY_STORE_ID)
        throw new Error('BTCPay is not configured');
    return `${env.BTCPAY_URL.replace(/\/$/, '')}/api/v1/stores/${env.BTCPAY_STORE_ID}${path}`;
}
export async function createInvoice(input) {
    if (env.USE_MOCK_BTCPAY) {
        return {
            id: `mock_${input.orderId}`,
            checkoutLink: `${env.APP_URL.replace(/\/$/, '')}/mock-btcpay?purchase=${input.orderId}`,
            status: 'New'
        };
    }
    if (!env.BTCPAY_API_KEY)
        throw new Error('BTCPay API key is not configured');
    const response = await fetch(apiUrl('/invoices'), {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `token ${env.BTCPAY_API_KEY}` },
        body: JSON.stringify({
            amount: input.amount,
            currency: input.currency || env.BTCPAY_CURRENCY,
            metadata: { orderId: input.orderId, buyerEmail: input.buyerEmail },
            checkout: { redirectURL: input.redirectUrl, redirectAutomatically: true }
        })
    });
    if (!response.ok)
        throw new Error(`BTCPay invoice failed: ${response.status} ${await response.text()}`);
    return response.json();
}
export function verifyWebhook(rawBody, signatureHeader) {
    if (env.USE_MOCK_BTCPAY)
        return true;
    if (!env.BTCPAY_WEBHOOK_SECRET)
        return false;
    if (!signatureHeader)
        return false;
    const expected = 'sha256=' + crypto.createHmac('sha256', env.BTCPAY_WEBHOOK_SECRET).update(rawBody).digest('hex');
    const a = Buffer.from(expected);
    const b = Buffer.from(signatureHeader);
    return a.length === b.length && crypto.timingSafeEqual(a, b);
}

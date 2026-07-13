import crypto from 'node:crypto';
import { env } from '../config/env.js';
function requireApiKey() {
    if (!env.NOWPAYMENTS_API_KEY) {
        throw new Error('NOWPAYMENTS_API_KEY is not configured');
    }
    return env.NOWPAYMENTS_API_KEY;
}
function sortObject(value) {
    if (Array.isArray(value))
        return value.map(sortObject);
    if (value && typeof value === 'object') {
        return Object.keys(value).sort().reduce((acc, key) => {
            acc[key] = sortObject(value[key]);
            return acc;
        }, {});
    }
    return value;
}
export function verifyNowPaymentsSignature(body, signature) {
    if (!env.NOWPAYMENTS_IPN_SECRET)
        return true;
    const sig = Array.isArray(signature) ? signature[0] : signature;
    if (!sig)
        return false;
    const sortedBody = sortObject(body);
    const stringified = JSON.stringify(sortedBody);
    const expected = crypto
        .createHmac('sha512', env.NOWPAYMENTS_IPN_SECRET)
        .update(stringified)
        .digest('hex');
    const a = Buffer.from(String(sig));
    const b = Buffer.from(expected);
    return a.length === b.length && crypto.timingSafeEqual(a, b);
}
export async function createPayment(orderId, priceCents, currency = 'usd', orderDescription = 'Readora ebook purchase') {
    const apiKey = requireApiKey();
    const priceAmount = Math.max(0, Number(priceCents || 0) / 100);
    const body = {
        price_amount: priceAmount,
        price_currency: currency.toLowerCase(),
        pay_currency: 'btc',
        order_id: orderId,
        order_description: orderDescription,
        ipn_callback_url: `${env.APP_URL.replace(/\/$/, '')}/api/webhooks/nowpayments`
    };
    const response = await fetch('https://api.nowpayments.io/v1/payment', {
        method: 'POST',
        headers: {
            'x-api-key': apiKey,
            'content-type': 'application/json'
        },
        body: JSON.stringify(body)
    });
    const text = await response.text();
    let data;
    try {
        data = text ? JSON.parse(text) : {};
    }
    catch {
        throw new Error(`NOWPayments returned non-JSON response: ${text}`);
    }
    if (!response.ok) {
        const message = data.message ||
            data.error ||
            JSON.stringify(data) ||
            `NOWPayments payment failed with status ${response.status}`;
        throw new Error(message);
    }
    const paymentId = String(data.payment_id || data.purchase_id || data.order_id || orderId);
    const payAddress = String(data.pay_address || '');
    const payAmount = data.pay_amount ? String(data.pay_amount) : '';
    const paymentUrl = String(data.invoice_url || data.payment_url || data.pay_url || data.payment_link || '') ||
        (payAddress ? `bitcoin:${payAddress}${payAmount ? `?amount=${payAmount}` : ''}` : 'https://nowpayments.io');
    return {
        paymentId,
        paymentUrl,
        payAddress,
        raw: data
    };
}

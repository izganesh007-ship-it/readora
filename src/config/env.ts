import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(8080),
  APP_URL: z.string().url().default('http://localhost:8080'),
  DATABASE_URL: z.string().min(1),
  COOKIE_SECRET: z.string().min(16).default('dev_cookie_secret_change_me'),
  JWT_SECRET: z.string().min(16).default('dev_jwt_secret_change_me'),
  CORS_ORIGIN: z.string().default('http://localhost:3000'),

  CONFIG_AUTO_UPGRADE: z.coerce.boolean().default(true),
  BTCPAY_MODE: z.enum(['auto', 'mock', 'live', 'nowpayments']).default('auto'),

  STORAGE_DRIVER: z.enum(['auto', 'local', 's3', 'r2']).default('auto'),
  LOCAL_STORAGE_DIR: z.string().default('./storage'),

  BTCPAY_URL: z.string().url().optional(),
  BTCPAY_API_KEY: z.string().optional(),
  BTCPAY_STORE_ID: z.string().optional(),
  BTCPAY_WEBHOOK_SECRET: z.string().optional(),
  BTCPAY_CURRENCY: z.string().default('USD'),

  NOWPAYMENTS_API_KEY: z.string().optional(),
  NOWPAYMENTS_IPN_SECRET: z.string().optional(),

  R2_ENDPOINT: z.string().optional(),
  R2_ACCESS_KEY_ID: z.string().optional(),
  R2_SECRET_ACCESS_KEY: z.string().optional(),
  R2_BUCKET: z.string().optional(),
  R2_REGION: z.string().default('auto'),

  SIGNED_URL_SECONDS: z.coerce.number().default(300),
  DOWNLOAD_TOKEN_HOURS: z.coerce.number().default(24),

  LOGIN_RATE_LIMIT_WINDOW_MIN: z.coerce.number().default(15),
  LOGIN_RATE_LIMIT_MAX: z.coerce.number().default(5),
  API_RATE_LIMIT_WINDOW_MIN: z.coerce.number().default(15),
  API_RATE_LIMIT_MAX: z.coerce.number().default(300)
});

const parsed = schema.parse(process.env);

const hasBtcpayConfig = Boolean(
  parsed.BTCPAY_URL &&
  parsed.BTCPAY_API_KEY &&
  parsed.BTCPAY_STORE_ID &&
  parsed.BTCPAY_WEBHOOK_SECRET
);

const hasNowPaymentsConfig = Boolean(parsed.NOWPAYMENTS_API_KEY);

const hasR2Config = Boolean(
  parsed.R2_ENDPOINT &&
  parsed.R2_ACCESS_KEY_ID &&
  parsed.R2_SECRET_ACCESS_KEY &&
  parsed.R2_BUCKET
);

const useNowPayments =
  parsed.BTCPAY_MODE === 'nowpayments' ||
  (parsed.BTCPAY_MODE === 'auto' && hasNowPaymentsConfig);

const useMockBtcpay = parsed.BTCPAY_MODE === 'mock'
  ? true
  : parsed.BTCPAY_MODE === 'live'
    ? false
    : parsed.BTCPAY_MODE === 'nowpayments'
      ? false
      : !hasBtcpayConfig && !useNowPayments;

const activeStorageDriver = parsed.STORAGE_DRIVER === 'auto'
  ? (hasR2Config ? 's3' : 'local')
  : parsed.STORAGE_DRIVER === 'local' && parsed.CONFIG_AUTO_UPGRADE && hasR2Config
    ? 's3'
    : parsed.STORAGE_DRIVER;

export const env = {
  ...parsed,
  STORAGE_DRIVER_REQUESTED: parsed.STORAGE_DRIVER,
  STORAGE_DRIVER: activeStorageDriver as 'local' | 's3' | 'r2',
  HAS_BTCPAY_CONFIG: hasBtcpayConfig,
  HAS_NOWPAYMENTS_CONFIG: hasNowPaymentsConfig,
  HAS_R2_CONFIG: hasR2Config,
  USE_NOWPAYMENTS: useNowPayments,
  USE_MOCK_BTCPAY: useMockBtcpay
};

export const isProd = env.NODE_ENV === 'production';

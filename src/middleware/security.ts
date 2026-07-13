import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { env, isProd } from '../config/env.js';

export const corsMiddleware = cors({
  origin: env.CORS_ORIGIN.split(',').map(v => v.trim()),
  credentials: true
});

export const helmetMiddleware = helmet({
  contentSecurityPolicy: {
    useDefaults: true,
    directives: {
      "default-src": ["'self'"],
      "script-src": ["'self'", "'unsafe-inline'"],
      "style-src": ["'self'", "'unsafe-inline'"],
      "img-src": ["'self'", "data:", "blob:"],
      "connect-src": ["'self'", env.BTCPAY_URL || "'self'"],
      "frame-ancestors": ["'none'"]
    }
  },
  hsts: isProd ? { maxAge: 31536000, includeSubDomains: true, preload: true } : false
});

export const apiLimiter = rateLimit({
  windowMs: env.API_RATE_LIMIT_WINDOW_MIN * 60_000,
  limit: env.API_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false
});

export const loginLimiter = rateLimit({
  windowMs: env.LOGIN_RATE_LIMIT_WINDOW_MIN * 60_000,
  limit: env.LOGIN_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many login attempts. Try again later.' }
});

import type { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

export type AdminSession = { adminId: string; role: 'OWNER' | 'ADMIN' | 'EDITOR' | 'SUPPORT' };

declare global {
  namespace Express { interface Request { admin?: AdminSession } }
}

export function signAdminSession(payload: AdminSession) {
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: '2h', issuer: 'readora' });
}

export function requireAdmin(roles: AdminSession['role'][] = ['OWNER', 'ADMIN', 'EDITOR', 'SUPPORT']) {
  return (req: Request, res: Response, next: NextFunction) => {
    const token = req.cookies?.admin_session || req.headers.authorization?.replace(/^Bearer\s+/i, '');
    if (!token) return res.status(401).json({ error: 'Authentication required' });
    try {
      const decoded = jwt.verify(token, env.JWT_SECRET, { issuer: 'readora' }) as AdminSession;
      if (!roles.includes(decoded.role)) return res.status(403).json({ error: 'Insufficient role' });
      req.admin = decoded;
      next();
    } catch {
      return res.status(401).json({ error: 'Invalid or expired session' });
    }
  };
}

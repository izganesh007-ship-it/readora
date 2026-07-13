import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
export function signAdminSession(payload) {
    return jwt.sign(payload, env.JWT_SECRET, { expiresIn: '2h', issuer: 'readora' });
}
export function requireAdmin(roles = ['OWNER', 'ADMIN', 'EDITOR', 'SUPPORT']) {
    return (req, res, next) => {
        const token = req.cookies?.admin_session || req.headers.authorization?.replace(/^Bearer\s+/i, '');
        if (!token)
            return res.status(401).json({ error: 'Authentication required' });
        try {
            const decoded = jwt.verify(token, env.JWT_SECRET, { issuer: 'readora' });
            if (!roles.includes(decoded.role))
                return res.status(403).json({ error: 'Insufficient role' });
            req.admin = decoded;
            next();
        }
        catch {
            return res.status(401).json({ error: 'Invalid or expired session' });
        }
    };
}

import { query } from '../db.js';
export async function audit(action, opts = {}) {
    await query(`INSERT INTO audit_logs(actor_admin_id, action, entity_type, entity_id, ip, metadata)
     VALUES ($1,$2,$3,$4,$5,$6)`, [opts.adminId || null, action, opts.entityType || null, opts.entityId || null, opts.ip || null, JSON.stringify(opts.metadata || {})]);
}

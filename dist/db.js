import pg from 'pg';
import { env } from './config/env.js';
export const pool = new pg.Pool({ connectionString: env.DATABASE_URL, max: 20, idleTimeoutMillis: 30000 });
export async function query(text, params = []) {
    const result = await pool.query(text, params);
    return result;
}
export async function tx(fn) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const out = await fn(client);
        await client.query('COMMIT');
        return out;
    }
    catch (err) {
        await client.query('ROLLBACK');
        throw err;
    }
    finally {
        client.release();
    }
}

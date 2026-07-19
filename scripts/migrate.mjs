import fs from 'node:fs';
import pg from 'pg';

const sql = fs.readFileSync('sql/init.sql', 'utf8');
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

try {
  await pool.query(sql);
  console.log('Migration complete');
} catch (err) {
  console.error('Migration failed:', err);
  process.exit(1);
} finally {
  await pool.end();
}
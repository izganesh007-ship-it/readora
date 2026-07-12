import argon2 from 'argon2';
import { query } from '../db.js';

const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_INITIAL_PASSWORD;
if (!email || !password || password.length < 12) {
  console.error('Set ADMIN_EMAIL and ADMIN_INITIAL_PASSWORD with at least 12 characters.');
  process.exit(1);
}
const passwordHash = await argon2.hash(password, { type: argon2.argon2id, memoryCost: 19456, timeCost: 3, parallelism: 1 });
await query(
  `INSERT INTO admins(email,password_hash,role) VALUES($1,$2,'OWNER')
   ON CONFLICT(email) DO UPDATE SET password_hash=EXCLUDED.password_hash, role='OWNER', updated_at=now()`,
  [email, passwordHash]
);
console.log(`Admin ready: ${email}`);
process.exit(0);

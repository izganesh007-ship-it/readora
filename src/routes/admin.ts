import { Router } from 'express';
import argon2 from 'argon2';
import { z } from 'zod';
import { query } from '../db.js';
import { loginLimiter } from '../middleware/security.js';
import { requireAdmin, signAdminSession } from '../middleware/auth.js';
import { audit } from '../services/audit.js';
import { env, isProd } from '../config/env.js';

export const adminRouter = Router();

adminRouter.post('/login', loginLimiter, async (req, res, next) => {
  try {
    const body = z.object({
      email: z.string().email(),
      password: z.string().min(8),
      totp: z.string().optional()
    }).parse(req.body);

    const out = await query(
      'SELECT id,email,password_hash,role,locked_until FROM admins WHERE email=$1',
      [body.email]
    );

    if (!out.rowCount) return res.status(401).json({ error: 'Invalid credentials' });

    const admin = out.rows[0];

    if (admin.locked_until && new Date(admin.locked_until) > new Date()) {
      return res.status(423).json({ error: 'Account temporarily locked' });
    }

    const ok = await argon2.verify(admin.password_hash, body.password);

    if (!ok) {
      await query(
        `UPDATE admins
         SET failed_attempts=failed_attempts+1,
             locked_until=CASE WHEN failed_attempts>=4 THEN now()+interval '15 minutes' ELSE locked_until END
         WHERE id=$1`,
        [admin.id]
      );
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    await query(
      'UPDATE admins SET failed_attempts=0, locked_until=NULL, last_login_at=now() WHERE id=$1',
      [admin.id]
    );

    const token = signAdminSession({ adminId: admin.id, role: admin.role });

    res.cookie('admin_session', token, {
      httpOnly: true,
      secure: isProd,
      sameSite: 'lax',
      maxAge: 2 * 60 * 60 * 1000
    });

    await audit('ADMIN_LOGIN', { adminId: admin.id, ip: req.ip });

    res.json({
      ok: true,
      token,
      role: admin.role
    });
  } catch (err) {
    next(err);
  }
});

adminRouter.post('/logout', (_req, res) => {
  res.clearCookie('admin_session');
  res.json({ ok: true });
});

adminRouter.get('/analytics', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (_req, res, next) => {
  try {
    const [books, revenue, sales, downloads, views, trending] = await Promise.all([
      query('SELECT count(*)::int AS value FROM books'),
      query("SELECT COALESCE(sum(amount_cents),0)::int AS value FROM purchases WHERE status='PAID'"),
      query("SELECT count(*)::int AS value FROM purchases WHERE status='PAID'"),
      query("SELECT count(*)::int AS value FROM download_links WHERE status='USED'"),
      query('SELECT count(*)::int AS value FROM book_views'),
      query(`
        SELECT b.title,b.slug,count(v.id)::int AS views
        FROM books b
        LEFT JOIN book_views v ON v.book_id=b.id
        GROUP BY b.id
        ORDER BY views DESC
        LIMIT 10
      `)
    ]);

    res.json({
      totalBooks: books.rows[0].value,
      revenueCents: revenue.rows[0].value,
      sales: sales.rows[0].value,
      downloads: downloads.rows[0].value,
      views: views.rows[0].value,
      trending: trending.rows
    });
  } catch (err) {
    next(err);
  }
});

adminRouter.post('/books', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (req, res, next) => {
  try {
    const body = z.object({
      title: z.string().min(1),
      slug: z.string().min(1),
      author: z.string().min(1),
      categoryId: z.string().uuid().optional().nullable(),
      description: z.string().min(1),
      previewText: z.string().optional().nullable(),
      access: z.enum(['FREE', 'PAID']),
      priceCents: z.number().int().min(0),
      coverKey: z.string().optional().nullable(),
      epubKey: z.string().optional().nullable(),
      pdfKey: z.string().optional().nullable(),
      readerFormat: z.enum(['CHAPTERS', 'TXT', 'HTML', 'PDF']).default('CHAPTERS'),
      readerContent: z.string().optional().nullable(),
      readerContentKey: z.string().optional().nullable(),
      allowFreeDownload: z.boolean().default(false),
      featured: z.boolean().default(false)
    }).parse(req.body);

    const out = await query(
      `INSERT INTO books(
        title,slug,author,category_id,description,preview_text,access,price_cents,
        cover_key,epub_key,pdf_key,reader_format,reader_content,reader_content_key,
        allow_free_download,featured,published_at
      )
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,now())
      RETURNING id,slug`,
      [
        body.title,
        body.slug,
        body.author,
        body.categoryId || null,
        body.description,
        body.previewText || null,
        body.access,
        body.priceCents,
        body.coverKey || null,
        body.epubKey || null,
        body.pdfKey || null,
        body.readerFormat,
        body.readerContent || null,
        body.readerContentKey || null,
        body.allowFreeDownload,
        body.featured
      ]
    );

    await audit('BOOK_CREATED', {
      adminId: req.admin?.adminId,
      entityType: 'book',
      entityId: out.rows[0].id,
      ip: req.ip
    });

    res.status(201).json({ data: out.rows[0] });
  } catch (err) {
    next(err);
  }
});

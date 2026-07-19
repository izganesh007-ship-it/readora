import { Router } from 'express';
import argon2 from 'argon2';
import { z } from 'zod';
import { query } from '../db.js';
import { loginLimiter } from '../middleware/security.js';
import { requireAdmin, signAdminSession } from '../middleware/auth.js';
import { audit } from '../services/audit.js';
import { isProd } from '../config/env.js';

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

adminRouter.get('/books', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (req, res, next) => {
  try {
    const out = await query(`
      SELECT b.*, c.name AS category_name, c.slug AS category_slug
      FROM books b
      LEFT JOIN categories c ON c.id = b.category_id
      ORDER BY b.created_at DESC
    `);
    res.json({ data: out.rows });
  } catch (err) { next(err); }
});

adminRouter.get('/books/:id', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (req, res, next) => {
  try {
    const out = await query(`
      SELECT b.*, c.name AS category_name, c.slug AS category_slug
      FROM books b
      LEFT JOIN categories c ON c.id = b.category_id
      WHERE b.id = $1
    `, [req.params.id]);
    if (!out.rowCount) return res.status(404).json({ error: 'Book not found' });
    res.json({ data: out.rows[0] });
  } catch (err) { next(err); }
});

adminRouter.put('/books/:id', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (req, res, next) => {
  try {
    const body = z.object({
      title: z.string().min(1).optional(),
      slug: z.string().min(1).optional(),
      author: z.string().min(1).optional(),
      categoryId: z.string().uuid().optional().nullable(),
      description: z.string().min(1).optional(),
      previewText: z.string().optional().nullable(),
      access: z.enum(['FREE', 'PAID']).optional(),
      priceCents: z.number().int().min(0).optional(),
      coverKey: z.string().optional().nullable(),
      epubKey: z.string().optional().nullable(),
      pdfKey: z.string().optional().nullable(),
      readerFormat: z.enum(['CHAPTERS', 'TXT', 'HTML', 'PDF']).optional(),
      readerContent: z.string().optional().nullable(),
      readerContentKey: z.string().optional().nullable(),
      allowFreeDownload: z.boolean().optional(),
      featured: z.boolean().optional(),
      isActive: z.boolean().optional()
    }).parse(req.body);

    const fields: string[] = [];
    const params: unknown[] = [req.params.id];
    let idx = 2;

    for (const [key, value] of Object.entries(body)) {
      if (value === undefined) continue;
      const col = key.replace(/([A-Z])/g, '_$1').toLowerCase();
      fields.push(`${col} = $${idx++}`);
      params.push(value);
    }
    fields.push(`updated_at = now()`);

    const out = await query(
      `UPDATE books SET ${fields.join(', ')} WHERE id = $1 RETURNING *`,
      params
    );
    if (!out.rowCount) return res.status(404).json({ error: 'Book not found' });

    await audit('BOOK_UPDATED', { adminId: (req.admin?.adminId as string) ?? '', entityType: 'book', entityId: req.params.id as string, ip: req.ip });
    res.json({ data: out.rows[0] });
  } catch (err) { next(err); }
});

adminRouter.delete('/books/:id', requireAdmin(['OWNER', 'ADMIN']), async (req, res, next) => {
  try {
    const out = await query('DELETE FROM books WHERE id = $1 RETURNING id', [req.params.id]);
    if (!out.rowCount) return res.status(404).json({ error: 'Book not found' });
    await audit('BOOK_DELETED', { adminId: (req.admin?.adminId as string) ?? '', entityType: 'book', entityId: req.params.id as string, ip: req.ip });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

adminRouter.post('/categories', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (req, res, next) => {
  try {
    const body = z.object({
      name: z.string().min(1),
      slug: z.string().min(1),
      description: z.string().optional().nullable(),
      coverUrl: z.string().url().optional().nullable(),
      sortOrder: z.number().int().default(0),
      isActive: z.boolean().default(true)
    }).parse(req.body);

    const out = await query(
      `INSERT INTO categories(name,slug,description,cover_url,sort_order,is_active) VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,
      [body.name, body.slug, body.description || null, body.coverUrl || null, body.sortOrder || 0, body.isActive !== false]
    );
    res.status(201).json({ data: out.rows[0] });
  } catch (err) { next(err); }
});

adminRouter.get('/categories', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (req, res, next) => {
  try {
    const out = await query('SELECT * FROM categories ORDER BY sort_order, name');
    res.json({ data: out.rows });
  } catch (err) { next(err); }
});

adminRouter.put('/categories/:id', requireAdmin(['OWNER', 'ADMIN', 'EDITOR']), async (req, res, next) => {
  try {
    const body = z.object({
      name: z.string().min(1).optional(),
      slug: z.string().min(1).optional(),
      description: z.string().optional().nullable(),
      coverUrl: z.string().url().optional().nullable(),
      sortOrder: z.number().int().optional(),
      isActive: z.boolean().optional()
    }).parse(req.body);

    const fields: string[] = [];
    const params: unknown[] = [req.params.id];
    let idx = 2;
    for (const [key, value] of Object.entries(body)) {
      if (value === undefined) continue;
      const col = key.replace(/([A-Z])/g, '_$1').toLowerCase();
      fields.push(`${col} = $${idx++}`);
      params.push(value);
    }
    const out = await query(`UPDATE categories SET ${fields.join(', ')} WHERE id = $1 RETURNING *`, params);
    if (!out.rowCount) return res.status(404).json({ error: 'Category not found' });
    res.json({ data: out.rows[0] });
  } catch (err) { next(err); }
});

adminRouter.delete('/categories/:id', requireAdmin(['OWNER', 'ADMIN']), async (req, res, next) => {
  try {
    const out = await query('DELETE FROM categories WHERE id = $1 RETURNING id', [req.params.id]);
    if (!out.rowCount) return res.status(404).json({ error: 'Category not found' });
    res.json({ ok: true });
  } catch (err) { next(err); }
});

import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
export const booksRouter = Router();
booksRouter.get('/', async (req, res, next) => {
    try {
        const q = z.object({
            q: z.string().optional(),
            category: z.string().optional(),
            access: z.enum(['FREE', 'PAID']).optional(),
            sort: z.enum(['popularity', 'newest', 'price', 'rating']).default('popularity'),
            page: z.coerce.number().min(1).default(1),
            limit: z.coerce.number().min(1).max(60).default(24)
        }).parse(req.query);
        const where = ['b.is_active = true'];
        const params = [];
        if (q.q) {
            params.push(q.q);
            where.push(`b.search_vector @@ websearch_to_tsquery('english', $${params.length})`);
        }
        if (q.category) {
            params.push(q.category);
            where.push(`c.slug = $${params.length}`);
        }
        if (q.access) {
            params.push(q.access);
            where.push(`b.access = $${params.length}`);
        }
        const order = q.sort === 'newest' ? 'b.published_at DESC NULLS LAST' : q.sort === 'price' ? 'b.price_cents ASC' : q.sort === 'rating' ? 'b.rating DESC' : 'b.popularity_score DESC';
        params.push(q.limit, (q.page - 1) * q.limit);
        const rows = await query(`SELECT b.id,b.title,b.slug,b.author,b.description,b.access,b.price_cents,b.currency,b.cover_key,b.rating,b.review_count,b.popularity_score,c.name AS category,c.slug AS category_slug
       FROM books b LEFT JOIN categories c ON c.id=b.category_id
       WHERE ${where.join(' AND ')}
       ORDER BY ${order}
       LIMIT $${params.length - 1} OFFSET $${params.length}`, params);
        res.json({ data: rows.rows, page: q.page, limit: q.limit });
    }
    catch (err) {
        next(err);
    }
});
booksRouter.get('/:slug', async (req, res, next) => {
    try {
        const row = await query(`SELECT b.*, c.name AS category,
        COALESCE(json_agg(DISTINCT t.name) FILTER (WHERE t.id IS NOT NULL), '[]') AS tags
       FROM books b
       LEFT JOIN categories c ON c.id=b.category_id
       LEFT JOIN book_tags bt ON bt.book_id=b.id
       LEFT JOIN tags t ON t.id=bt.tag_id
       WHERE b.slug=$1 AND b.is_active=true
       GROUP BY b.id,c.name`, [req.params.slug]);
        if (!row.rowCount)
            return res.status(404).json({ error: 'Book not found' });
        await query('INSERT INTO book_views(book_id, ip_hash, user_agent) VALUES ($1, encode(digest($2,\'sha256\'),\'hex\'), $3)', [row.rows[0].id, req.ip || '', req.get('user-agent') || '']);
        res.json({ data: row.rows[0] });
    }
    catch (err) {
        next(err);
    }
});

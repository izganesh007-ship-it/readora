import { Router } from 'express';
import { query } from '../db.js';
export const categoriesRouter = Router();
categoriesRouter.get('/', async (_req, res, next) => {
    try {
        const out = await query(`SELECT c.*, count(b.id)::int AS book_count FROM categories c LEFT JOIN books b ON b.category_id=c.id AND b.is_active=true WHERE c.is_active=true GROUP BY c.id ORDER BY c.sort_order,c.name`);
        res.json({ data: out.rows });
    }
    catch (err) {
        next(err);
    }
});

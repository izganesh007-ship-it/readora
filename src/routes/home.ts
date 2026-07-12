import { Router } from 'express';
import { query } from '../db.js';

export const homeRouter = Router();

homeRouter.get('/', async (_req, res, next) => {
  try {
    const [featured, trending, newest, sections] = await Promise.all([
      query(`SELECT b.slug,b.title,b.author,b.description,b.access,b.price_cents,b.cover_key,b.rating,c.name AS category FROM books b LEFT JOIN categories c ON c.id=b.category_id WHERE b.is_active=true AND b.featured=true ORDER BY b.popularity_score DESC LIMIT 8`),
      query(`SELECT b.slug,b.title,b.author,b.access,b.price_cents,b.cover_key,b.rating,c.name AS category FROM books b LEFT JOIN categories c ON c.id=b.category_id WHERE b.is_active=true ORDER BY b.popularity_score DESC LIMIT 18`),
      query(`SELECT b.slug,b.title,b.author,b.access,b.price_cents,b.cover_key,b.rating,c.name AS category FROM books b LEFT JOIN categories c ON c.id=b.category_id WHERE b.is_active=true ORDER BY b.published_at DESC NULLS LAST LIMIT 18`),
      query(`SELECT hs.id,hs.title,hs.slug,hs.section_type,hs.sort_order,
        COALESCE(json_agg(json_build_object('slug',b.slug,'title',b.title,'author',b.author,'access',b.access,'priceCents',b.price_cents,'coverKey',b.cover_key,'rating',b.rating) ORDER BY hsb.sort_order) FILTER (WHERE b.id IS NOT NULL),'[]') AS books
        FROM homepage_sections hs
        LEFT JOIN homepage_section_books hsb ON hsb.section_id=hs.id
        LEFT JOIN books b ON b.id=hsb.book_id AND b.is_active=true
        WHERE hs.is_active=true GROUP BY hs.id ORDER BY hs.sort_order`)
    ]);
    res.json({ featured: featured.rows, trending: trending.rows, newest: newest.rows, sections: sections.rows });
  } catch (err) { next(err); }
});

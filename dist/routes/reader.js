import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { readTextObject, signedObjectUrl } from '../services/storage.js';
export const readerRouter = Router();
readerRouter.get('/:slug', async (req, res, next) => {
    try {
        const book = await query('SELECT id,title,slug,author,access,reader_format,reader_content,reader_content_key,allow_free_download FROM books WHERE slug=$1 AND is_active=true', [req.params.slug]);
        if (!book.rowCount)
            return res.status(404).json({ error: 'Book not found' });
        const b = book.rows[0];
        if (b.access !== 'FREE')
            return res.status(402).json({ error: 'Purchase required. Paid books cannot be read online before purchase.' });
        if (b.reader_format === 'PDF') {
            const key = b.reader_content_key;
            if (!key)
                return res.status(404).json({ error: 'PDF reader file not configured' });
            const pdfUrl = await signedObjectUrl(key, `${b.title}.pdf`, 'inline');
            return res.json({ book: b, mode: 'PDF', pdfUrl, allowDownload: Boolean(b.allow_free_download) });
        }
        if (b.reader_format === 'HTML' || b.reader_format === 'TXT') {
            const content = b.reader_content_key ? await readTextObject(b.reader_content_key) : (b.reader_content || '');
            return res.json({ book: b, mode: b.reader_format, content, allowDownload: Boolean(b.allow_free_download) });
        }
        const chapters = await query('SELECT chapter_index,title,content FROM book_chapters WHERE book_id=$1 ORDER BY chapter_index', [b.id]);
        res.json({ book: b, mode: 'CHAPTERS', chapters: chapters.rows, allowDownload: Boolean(b.allow_free_download) });
    }
    catch (err) {
        next(err);
    }
});
readerRouter.put('/:slug/progress', async (req, res, next) => {
    try {
        const body = z.object({ anonKey: z.string().min(10).optional(), userId: z.string().uuid().optional(), chapterIndex: z.number().int().min(0), percent: z.number().min(0).max(100) }).parse(req.body);
        if (!body.anonKey && !body.userId)
            return res.status(400).json({ error: 'anonKey or userId required' });
        const book = await query('SELECT id,access FROM books WHERE slug=$1 AND is_active=true', [req.params.slug]);
        if (!book.rowCount)
            return res.status(404).json({ error: 'Book not found' });
        if (book.rows[0].access !== 'FREE')
            return res.status(402).json({ error: 'Purchase required' });
        const constraint = body.userId ? 'reader_progress_user_id_book_id_key' : 'reader_progress_anon_key_book_id_key';
        await query(`INSERT INTO reader_progress(user_id, anon_key, book_id, chapter_index, percent, updated_at)
       VALUES($1,$2,$3,$4,$5,now())
       ON CONFLICT ON CONSTRAINT ${constraint} DO UPDATE SET chapter_index=EXCLUDED.chapter_index, percent=EXCLUDED.percent, updated_at=now()`, [body.userId || null, body.anonKey || null, book.rows[0].id, body.chapterIndex, body.percent]);
        res.json({ ok: true });
    }
    catch (err) {
        next(err);
    }
});

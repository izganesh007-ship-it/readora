import { Router } from 'express';
import { z } from 'zod';
import multer from 'multer';
import { requireAdmin } from '../middleware/auth.js';
import { signedUploadTarget, saveLocalObject } from '../services/storage.js';
import { audit } from '../services/audit.js';

export const uploadsRouter = Router();

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 200 * 1024 * 1024 } });

uploadsRouter.post('/sign', requireAdmin(['OWNER','ADMIN','EDITOR']), async (req, res, next) => {
  try {
    const body = z.object({
      kind: z.enum(['cover','epub','pdf','reader-html','reader-txt','reader-pdf']),
      filename: z.string().min(1),
      contentType: z.string().min(3)
    }).parse(req.body);
    const target = await signedUploadTarget(body);
    await audit('UPLOAD_TARGET_CREATED', { adminId: req.admin?.adminId, ip: req.ip, metadata: { key: target.key, kind: body.kind } });
    res.json(target);
  } catch (err) { next(err); }
});

// File upload via multipart form (covers, epubs, PDFs)
uploadsRouter.post('/local', requireAdmin(['OWNER','ADMIN','EDITOR']), upload.single('file'), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    const kind = req.body.kind || 'cover';
    const key = `uploads/${kind}/${Date.now()}-${req.file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_')}`;
    await saveLocalObject(key, req.file.buffer);
    await audit('LOCAL_FILE_UPLOADED', { adminId: req.admin?.adminId, ip: req.ip, metadata: { key, kind, bytes: req.file.size } });
    res.status(201).json({ key, bytes: req.file.size });
  } catch (err) { next(err); }
});

// Base64 upload for small files (alternative to multipart)
uploadsRouter.post('/base64', requireAdmin(['OWNER','ADMIN','EDITOR']), async (req, res, next) => {
  try {
    const body = z.object({ key: z.string().min(3), contentBase64: z.string().min(1) }).parse(req.body);
    const buf = Buffer.from(body.contentBase64, 'base64');
    await saveLocalObject(body.key, buf);
    await audit('LOCAL_FILE_UPLOADED', { adminId: req.admin?.adminId, ip: req.ip, metadata: { key: body.key, bytes: buf.length } });
    res.status(201).json({ key: body.key, bytes: buf.length });
  } catch (err) { next(err); }
});

import { Router } from 'express';
import { z } from 'zod';
import { requireAdmin } from '../middleware/auth.js';
import { signedUploadTarget, saveLocalObject } from '../services/storage.js';
import { audit } from '../services/audit.js';

export const uploadsRouter = Router();

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

// Free/local deployment helper: upload small files as base64 JSON when STORAGE_DRIVER=local.
// For large PDFs in production, use signed R2/S3 PUT upload from /sign.
uploadsRouter.post('/local', requireAdmin(['OWNER','ADMIN','EDITOR']), async (req, res, next) => {
  try {
    const body = z.object({ key: z.string().min(3), contentBase64: z.string().min(1) }).parse(req.body);
    const buf = Buffer.from(body.contentBase64, 'base64');
    await saveLocalObject(body.key, buf);
    await audit('LOCAL_FILE_UPLOADED', { adminId: req.admin?.adminId, ip: req.ip, metadata: { key: body.key, bytes: buf.length } });
    res.status(201).json({ key: body.key, bytes: buf.length });
  } catch (err) { next(err); }
});

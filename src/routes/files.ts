import { Router } from 'express';
import fs from 'node:fs';
import { localPathForKey, signedObjectUrl } from '../services/storage.js';
import { verifyLocalFileToken } from '../services/localFileToken.js';
import { env } from '../config/env.js';

export const filesRouter = Router();

filesRouter.get('/:token', (req, res) => {
  const payload = verifyLocalFileToken(req.params.token);
  if (!payload) return res.status(410).json({ error: 'File link expired or invalid' });
  const filePath = localPathForKey(payload.key);
  if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'File not found' });
  res.setHeader('Content-Disposition', `${payload.disposition}; filename="${payload.filename.replace(/"/g, '')}"`);
  res.sendFile(filePath);
});

// Serve cover images by storage key
filesRouter.get('/cover', async (req, res, next) => {
  try {
    const key = req.query.key as string;
    if (!key) return res.status(400).json({ error: 'Missing key parameter' });
    if (env.STORAGE_DRIVER === 'local') {
      const filePath = localPathForKey(key);
      if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'Cover not found' });
      return res.sendFile(filePath);
    }
    // For S3/R2, redirect to signed URL
    const url = await signedObjectUrl(key, 'cover', 'inline');
    res.redirect(url);
  } catch (err) { next(err); }
});

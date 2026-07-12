import { Router } from 'express';
import fs from 'node:fs';
import { localPathForKey } from '../services/storage.js';
import { verifyLocalFileToken } from '../services/localFileToken.js';

export const filesRouter = Router();

filesRouter.get('/:token', (req, res) => {
  const payload = verifyLocalFileToken(req.params.token);
  if (!payload) return res.status(410).json({ error: 'File link expired or invalid' });
  const filePath = localPathForKey(payload.key);
  if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'File not found' });
  res.setHeader('Content-Disposition', `${payload.disposition}; filename="${payload.filename.replace(/"/g, '')}"`);
  res.sendFile(filePath);
});

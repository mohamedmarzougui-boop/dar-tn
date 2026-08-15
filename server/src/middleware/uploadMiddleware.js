import path from 'path';
import { fileURLToPath } from 'url';
import { randomUUID } from 'crypto';
import fs from 'fs';
import multer from 'multer';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// Resolved relative to this file, not process.cwd(), so it works the same
// regardless of which directory the server happens to be started from.
export const UPLOADS_DIR = path.join(__dirname, '../../uploads');

fs.mkdirSync(UPLOADS_DIR, { recursive: true });

const ALLOWED_MIME_TYPES = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
};

const storage = multer.diskStorage({
  destination: UPLOADS_DIR,
  // Never trust the client-supplied filename for the stored path (path
  // traversal / collision risk) - generate our own from a random UUID and
  // the extension implied by the validated MIME type.
  filename: (req, file, cb) => cb(null, `${randomUUID()}${ALLOWED_MIME_TYPES[file.mimetype]}`),
});

const fileFilter = (req, file, cb) => {
  if (!ALLOWED_MIME_TYPES[file.mimetype]) {
    return cb(new Error('Only JPEG, PNG, and WebP images are allowed.'));
  }
  cb(null, true);
};

export const uploadListingImages = multer({
  storage,
  fileFilter,
  limits: { fileSize: 5 * 1024 * 1024, files: 10 },
}).array('images', 10);

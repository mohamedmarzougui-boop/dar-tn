import { Router } from 'express';
import { body, param } from 'express-validator';
import { getModerationQueue, moderateListing } from '../controllers/adminController.js';
import { authenticateToken, requireAdmin } from '../middleware/authMiddleware.js';
import { validateRequest } from '../middleware/validateMiddleware.js';

const router = Router();

router.use(authenticateToken, requireAdmin);

router.get('/listings', getModerationQueue);
router.patch(
  '/listings/:id/status',
  param('id').isUUID(),
  body('status').isIn(['ACTIVE', 'ARCHIVED']).withMessage('status must be ACTIVE or ARCHIVED'),
  validateRequest,
  moderateListing
);

export default router;

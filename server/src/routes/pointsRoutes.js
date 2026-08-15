import { Router } from 'express';
import { body } from 'express-validator';
import { unlockContact, getPointsHistory } from '../controllers/pointsController.js';
import { authenticateToken } from '../middleware/authMiddleware.js';
import { validateRequest } from '../middleware/validateMiddleware.js';

const router = Router();

router.post(
  '/unlock',
  authenticateToken,
  body('listing_id').isUUID().withMessage('A valid listing_id is required'),
  validateRequest,
  unlockContact
);
router.get('/history', authenticateToken, getPointsHistory);

export default router;

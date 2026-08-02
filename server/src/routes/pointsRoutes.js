import { Router } from 'express';
import { unlockContact, getPointsHistory } from '../controllers/pointsController.js';
import { authenticateToken } from '../middleware/authMiddleware.js';

const router = Router();

// Protected Routes (Requires JWT Token)
router.post('/unlock', authenticateToken, unlockContact);
router.get('/history', authenticateToken, getPointsHistory);

export default router;
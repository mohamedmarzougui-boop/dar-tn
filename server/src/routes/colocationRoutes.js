import { Router } from 'express';
import { getColocationListings, createColocationPost } from '../controllers/colocationController.js';
import { authenticateToken } from '../middleware/authMiddleware.js';

const router = Router();

// Public colocation search
router.get('/', getColocationListings);

// Protected colocation post creation
router.post('/', authenticateToken, createColocationPost);

export default router;